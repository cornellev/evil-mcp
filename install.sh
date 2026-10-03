#!/usr/bin/env bash
# Register the EVIL MCP server globally for every supported client found on
# this machine, so it works from any project (not just inside this repo).
# Safe to re-run. Requires being on the CEV tailnet to actually connect.
#
#   ./install.sh              install for all detected clients
#   ./install.sh --dry-run    show what would change
#   EVIL_MCP_URL=http://host:8765/mcp ./install.sh   override the endpoint
set -euo pipefail

URL="${EVIL_MCP_URL:-http://100.122.165.58:8765/mcp}"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
root="$(cd "$(dirname "$0")" && pwd)"

run() { if ((DRY)); then echo "  [dry-run] $*"; else "$@"; fi; }
found=0

echo "EVIL endpoint: $URL"

# --- Claude Code: MCP server (user scope) + the skill ---
if command -v claude >/dev/null 2>&1; then
  found=1
  echo "Claude Code:"
  # Only a user-scope entry counts: running from inside this repo also "finds"
  # the project-scoped .mcp.json, which doesn't carry over to other directories.
  if claude mcp get evil 2>/dev/null | grep -q "Scope: User"; then
    echo "  evil MCP already registered globally, leaving as is"
  else
    run claude mcp add --transport http --scope user evil "$URL"
  fi
  run mkdir -p "$HOME/.claude/skills/evil"
  run cp "$root/.claude/skills/evil/SKILL.md" "$HOME/.claude/skills/evil/SKILL.md"
fi

# --- Codex ---
if command -v codex >/dev/null 2>&1; then
  found=1
  echo "Codex:"
  if codex mcp get evil >/dev/null 2>&1; then
    echo "  evil MCP already registered, leaving as is"
  else
    run codex mcp add evil --url "$URL"
  fi
  echo "  note: Codex reads guidance from AGENTS.md in the project you open; to get it"
  echo "  everywhere, append this repo's AGENTS.md to ~/.codex/AGENTS.md yourself."
fi

# --- Cursor: merge into ~/.cursor/mcp.json without clobbering other servers ---
if command -v cursor >/dev/null 2>&1 || [[ -d "$HOME/.cursor" ]]; then
  found=1
  echo "Cursor:"
  cfg="$HOME/.cursor/mcp.json"
  if ((DRY)); then
    echo "  [dry-run] merge evil into $cfg"
  else
    mkdir -p "$HOME/.cursor"
    python3 - "$cfg" "$URL" <<'PY'
import json, os, sys
path, url = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path) as f:
        text = f.read().strip()
    if text:
        data = json.loads(text)
data.setdefault("mcpServers", {})["evil"] = {"url": url}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"  wrote evil entry to {path}")
PY
  fi
fi

((found)) || echo "No Claude Code, Codex or Cursor found. Use the web UI, or see README.md."
echo "Done. Restart your client, then ask it: \"list the EVIL runs\"."
