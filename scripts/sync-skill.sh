#!/usr/bin/env bash
# AGENTS.md is the single source of truth for EVIL guidance. Claude Code wants
# it as a skill (frontmatter + body), so this regenerates the skill from it.
#   scripts/sync-skill.sh          rewrite the skill
#   scripts/sync-skill.sh --check  exit 1 if the skill is stale (for CI/pre-commit)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/.claude/skills/evil/SKILL.md"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
{
  cat <<'HEADER'
---
name: evil
description: Query Cornell Electric Vehicles' EVIL telemetry database (runs, turns, laps, straights, energy, uploaded recordings) through the `evil` and `evil-raw` MCP servers. Use for any question about recorded car runs, turn or lap performance, or finding and inspecting raw recordings.
---

HEADER
  cat "$root/AGENTS.md"
} > "$tmp"
if [[ "${1:-}" == "--check" ]]; then
  cmp -s "$tmp" "$out" || { echo "SKILL.md is stale; run scripts/sync-skill.sh" >&2; exit 1; }
else
  cp "$tmp" "$out"
fi
