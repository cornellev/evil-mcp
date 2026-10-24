#!/usr/bin/env bash
# Register the EVIL MCP servers and guidance for every supported client found
# on this machine. Requires being on the CEV tailnet to actually connect.
#
# This is also the update script: `git pull && ./install.sh` (with the same
# --project flag you installed with). Re-running adds any new servers,
# re-points entries whose URL changed and refreshes the skill.
#
#   ./install.sh                       install globally: EVIL is on in every project
#   ./install.sh --project DIR         install only for DIR and its subdirectories
#   ./install.sh --uninstall           remove the global install
#   ./install.sh --uninstall --project DIR   remove it from DIR
#   ./install.sh --dry-run ...         show what would change
#   EVIL_MCP_URL=http://host:8765/mcp ./install.sh   override the curated endpoint
#   EVIL_RAW_URL=http://host:8767/mcp ./install.sh   override the raw-SQL endpoint
#
# Registers two servers: `evil` (curated tools, port 8765) and `evil-raw`
# (free-form read-only SQL over stored recordings and the catalog, port 8767).
#
# --project writes DIR/.mcp.json and DIR/.claude/skills/evil/ (plus
# DIR/.cursor/mcp.json and DIR/.codex/config.toml if those clients are
# installed). If DIR is in a git repo, the new files are added to
# .git/info/exclude so they stay out of commits.
set -euo pipefail

URL="${EVIL_MCP_URL:-http://100.122.165.58:8765/mcp}"
RAW_URL="${EVIL_RAW_URL:-http://100.122.165.58:8767/mcp}"
DRY=0
UNINSTALL=0
PROJECT=""
usage() { sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//'; }
while (($#)); do
  case "$1" in
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --project)
      [[ $# -ge 2 ]] || { echo "--project needs a directory" >&2; exit 2; }
      PROJECT="$2"; shift ;;
    --project=*) PROJECT="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
root="$(cd "$(dirname "$0")" && pwd)"
if [[ -n "$PROJECT" ]]; then
  [[ -d "$PROJECT" ]] || { echo "not a directory: $PROJECT" >&2; exit 2; }
  PROJECT="$(cd "$PROJECT" && pwd)"
fi

run() { if ((DRY)); then echo "  [dry-run] $*"; else "$@"; fi; }
found=0
written=()  # project files this run created or changed, for git_exclude

# Add or remove the evil servers in a JSON {"mcpServers": {...}} file without
# touching any other server. $2 = "http" to include "type": "http".
json_servers() {
  local path="$1" with_type="${2:-}"
  if ((DRY)); then
    if ((UNINSTALL)); then echo "  [dry-run] remove evil and evil-raw from $path"
    else echo "  [dry-run] merge evil and evil-raw into $path"; fi
    return
  fi
  ((UNINSTALL)) && [[ ! -f "$path" ]] && { echo "  nothing to remove, no $path"; return; }
  mkdir -p "$(dirname "$path")"
  python3 - "$path" "$with_type" "$UNINSTALL" "$URL" "$RAW_URL" <<'PY'
import json, os, sys
path, with_type, uninstall, url, raw_url = sys.argv[1:6]
data = {}
if os.path.exists(path):
    with open(path) as f:
        text = f.read().strip()
    if text:
        data = json.loads(text)
servers = data.setdefault("mcpServers", {})
if uninstall == "1":
    removed = [n for n in ("evil", "evil-raw") if servers.pop(n, None) is not None]
    if not removed:
        print(f"  nothing to remove, no EVIL entries in {path}")
        sys.exit()
    if not servers and set(data) == {"mcpServers"}:
        os.remove(path)
        print(f"  removed {path} (it held only EVIL)")
        sys.exit()
    msg = f"  removed {' and '.join(removed)} from {path}"
else:
    for name, u in (("evil", url), ("evil-raw", raw_url)):
        servers[name] = {"type": "http", "url": u} if with_type == "http" else {"url": u}
    msg = f"  wrote evil and evil-raw entries to {path}"
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(msg)
PY
  ((UNINSTALL)) || written+=("$path")
}

# Same for a Codex config.toml: drop any [mcp_servers.evil*] tables, then
# append fresh ones unless uninstalling.
toml_servers() {
  local path="$1"
  if ((DRY)); then
    if ((UNINSTALL)); then echo "  [dry-run] remove evil and evil-raw from $path"
    else echo "  [dry-run] merge evil and evil-raw into $path"; fi
    return
  fi
  ((UNINSTALL)) && [[ ! -f "$path" ]] && { echo "  nothing to remove, no $path"; return; }
  mkdir -p "$(dirname "$path")"
  python3 - "$path" "$UNINSTALL" "$URL" "$RAW_URL" <<'PY'
import os, re, sys
path, uninstall, url, raw_url = sys.argv[1:5]
text = open(path).read() if os.path.exists(path) else ""
for name in ("evil", "evil-raw"):
    text = re.sub(rf"(?ms)^\[mcp_servers\.{re.escape(name)}\]\n.*?(?=^\[|\Z)", "", text)
text = text.rstrip("\n")
if uninstall != "1":
    text += ("\n\n" if text else "") + (
        f'[mcp_servers.evil]\nurl = "{url}"\n\n[mcp_servers.evil-raw]\nurl = "{raw_url}"'
    )
if text:
    with open(path, "w") as f:
        f.write(text + "\n")
elif os.path.exists(path):
    os.remove(path)
print(f"  {'removed EVIL from' if uninstall == '1' else 'wrote evil and evil-raw entries to'} {path}")
PY
  ((UNINSTALL)) || written+=("$path")
}

# Copy the Claude skill into a skills directory, or remove it.
skill() {
  local dir="$1/evil"
  if ((UNINSTALL)); then
    if [[ -f "$dir/SKILL.md" ]]; then
      run rm -f "$dir/SKILL.md"
      ((DRY)) || rmdir "$dir" "$1" "$(dirname "$1")" 2>/dev/null || true
      echo "  removed evil skill from $1"
    else
      echo "  nothing to remove, no evil skill in $1"
    fi
    return
  fi
  local src="$root/.claude/skills/evil/SKILL.md"
  if cmp -s "$src" "$dir/SKILL.md"; then
    echo "  evil skill in $1 already up to date"
    return
  fi
  if [[ -f "$dir/SKILL.md" ]]; then echo "  updating evil skill in $1"; else echo "  installing evil skill in $1"; fi
  run mkdir -p "$dir"
  run cp "$src" "$dir/SKILL.md"
  written+=("$dir/")
}

# The global Claude Code entry, looked up from / because inside a project a
# project-scoped .mcp.json (like this repo's) shadows it.
claude_user_entry() { (cd / && claude mcp get "$1" 2>/dev/null || true) | grep -A3 "Scope: User" || true; }

claude_register() {
  local name="$1" url="$2" info
  info="$(claude_user_entry "$name")"
  if ((UNINSTALL)); then
    if [[ -n "$info" ]]; then run claude mcp remove --scope user "$name"
    else echo "  nothing to remove, $name not registered globally"; fi
    return
  fi
  if [[ -n "$info" ]]; then
    if grep -qF "URL: $url" <<<"$info"; then
      echo "  $name MCP already registered globally, up to date"
      return
    fi
    echo "  $name MCP registered with a different URL, re-pointing it"
    run claude mcp remove --scope user "$name"
  fi
  run claude mcp add --transport http --scope user "$name" "$url"
}

codex_register() {
  local name="$1" url="$2"
  if ((UNINSTALL)); then
    if codex mcp get "$name" >/dev/null 2>&1; then run codex mcp remove "$name"
    else echo "  nothing to remove, $name not registered"; fi
  elif codex mcp get "$name" >/dev/null 2>&1; then
    echo "  $name MCP already registered, leaving as is"
  else
    run codex mcp add "$name" --url "$url"
  fi
}

# Keep project files this script wrote out of the project's commits: they are
# a personal choice, not something to push on everyone using that repo.
git_exclude() {
  ((DRY || UNINSTALL)) && return
  local top exclude f rel
  top="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)" || return 0
  exclude="$(cd "$PROJECT" && cd "$(git rev-parse --git-common-dir)" && pwd)/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  for f in "${written[@]}"; do
    rel="${f#"$top"/}"
    if git -C "$top" ls-files --error-unmatch "${rel%/}" >/dev/null 2>&1; then
      echo "  note: $rel is tracked in git, so the EVIL entries will show up in git status"
    elif ! grep -qxF "/$rel" "$exclude"; then
      echo "/$rel" >>"$exclude"
      echo "  added /$rel to .git/info/exclude (local only, never committed)"
    fi
  done
}

echo "EVIL endpoint: $URL"
echo "EVIL raw-SQL endpoint: $RAW_URL"
if [[ -n "$PROJECT" ]]; then echo "Scope: $PROJECT and its subdirectories"
else echo "Scope: global (every project)"; fi

# --- Claude Code ---
if command -v claude >/dev/null 2>&1; then
  found=1
  echo "Claude Code:"
  if [[ -n "$PROJECT" ]]; then
    json_servers "$PROJECT/.mcp.json" http
    skill "$PROJECT/.claude/skills"
    if ((!UNINSTALL)) && { [[ -n "$(claude_user_entry evil)" ]] || [[ -f "$HOME/.claude/skills/evil/SKILL.md" ]]; }; then
      echo "  note: EVIL is also installed globally, so it is still on in every project."
      echo "  Run ./install.sh --uninstall to remove the global install."
    fi
  else
    claude_register evil "$URL"
    claude_register evil-raw "$RAW_URL"
    skill "$HOME/.claude/skills"
  fi
fi

# --- Codex ---
if command -v codex >/dev/null 2>&1; then
  found=1
  echo "Codex:"
  if [[ -n "$PROJECT" ]]; then
    toml_servers "$PROJECT/.codex/config.toml"
    ((UNINSTALL)) || echo "  note: Codex reads a project's .codex/config.toml only once you trust that project."
  else
    codex_register evil "$URL"
    codex_register evil-raw "$RAW_URL"
  fi
  ((UNINSTALL)) || echo "  note: Codex reads guidance from AGENTS.md; copy or append this repo's AGENTS.md" \
    "into ${PROJECT:-~/.codex}/AGENTS.md yourself."
fi

# --- Cursor ---
if command -v cursor >/dev/null 2>&1 || [[ -d "$HOME/.cursor" ]]; then
  found=1
  echo "Cursor:"
  json_servers "${PROJECT:-$HOME}/.cursor/mcp.json"
fi

[[ -n "$PROJECT" ]] && git_exclude
((found)) || echo "No Claude Code, Codex or Cursor found. Use the web UI, or see README.md."
if ((UNINSTALL)); then
  echo "Done. Restart your client (or start a new session) to drop EVIL."
else
  echo "Done. Restart your client (or start a new session) so it reloads the servers and skill,"
  echo "then ask it: \"list the EVIL runs\"."
  echo "To update later: git pull && ./install.sh${PROJECT:+ --project $PROJECT}"
fi
