# evil-mcp

Connect your AI client to **EVIL**, Cornell Electric Vehicles' telemetry database
(runs, turns, laps, straights, energy, NAS recordings), so you can ask about the
car in plain English from Claude Code, Codex or Cursor.

> You must be on the CEV Tailscale network. The server is at
> `http://100.122.165.58:8765/mcp` (the NUC, `cev-nuc`). It is read-only.

## Just want a browser?

Open **http://100.122.165.58:8081** (EVIL-UI). Data browser plus a chat panel. No
setup.

## Fastest setup: one command

```bash
git clone https://github.com/cornellev/evil-mcp.git && cd evil-mcp && ./install.sh
```

`install.sh` registers EVIL globally for whichever of Claude Code, Codex and
Cursor it finds, so it works from any project. Re-running is safe;
`./install.sh --dry-run` shows what it would do. Restart your client afterwards,
then ask: *"List the EVIL runs."*

## Or: no install, just open this repo

The repo carries each client's project-level config, so opening this folder in the
client is enough: `.mcp.json` (Claude Code), `.cursor/mcp.json` (Cursor),
`.codex/config.toml` (Codex, trusted projects only). `AGENTS.md` (Codex, Cursor)
and the skill in `.claude/skills/evil/` (Claude Code) teach the model what the
tools mean. This works only while you are working in this folder, hence the
installer for everything else.

## Or: add it by hand

| Client | Command / config |
|---|---|
| Claude Code | `claude mcp add --transport http --scope user evil http://100.122.165.58:8765/mcp` |
| Codex | `codex mcp add evil --url http://100.122.165.58:8765/mcp` |
| Cursor | add `{"mcpServers": {"evil": {"url": "http://100.122.165.58:8765/mcp"}}}` to `~/.cursor/mcp.json` |

Any other MCP client: Streamable HTTP transport, that URL, no auth.

### Getting the guidance outside this repo

The server gives your model the tools; `AGENTS.md` gives it the know-how (what a
turn vs. a lap is, which tool to pick, how to write safe SQL). `install.sh` copies
the Claude skill to `~/.claude/skills/evil/` for you. For Codex and Cursor, copy
or append `AGENTS.md` into your own project, or into `~/.codex/AGENTS.md`.

## What you can ask

- "List the EVIL runs and tell me which is the most recent."
- "How was Turn 3 in run `<run_id>`?"
- "Compare laps 2 and 5. What changed in energy and average speed?"
- "Which turn instance had the best exit speed, and what was different about it?"
- "Where is the raw recording covering Turn 7 on the NAS?"

## Troubleshooting

- **Connection fails or hangs:** you are not on the tailnet, or the NUC is down.
  Check `tailscale status` shows `cev-nuc` as active.
- **Tools error or come back empty:** the server is up but the database may not be
  loaded yet. Tell the EVIL maintainers; it is not a problem with your setup.
- **Windows + WSL:** Cursor on Windows reads `%USERPROFILE%\.cursor\mcp.json`, not
  the WSL home directory; edit the Windows file instead.
- **Codex asks about OAuth:** the EVIL server has no auth. Update Codex, or set
  `auth` explicitly in your `config.toml` entry if your version requires it.

## Notes

- Verified against a real server: the endpoint and the nine tools respond. The
  Claude Code setup is tested by the author. The Codex and Cursor configs follow
  those clients' current documentation but have not been run end to end; fix the
  file and open a PR if one is off.
- Only the read port (`:8765`) is wired up here. EVIL's separate upload port is
  not part of this repo.
- Guidance lives once, in `AGENTS.md`. After editing it, run
  `scripts/sync-skill.sh` to regenerate the Claude skill
  (`scripts/sync-skill.sh --check` fails if they have drifted).
