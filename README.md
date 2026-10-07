# evil-mcp

Connect your AI client to **EVIL**, Cornell Electric Vehicles' telemetry database
(runs, turns, laps, straights, energy, NAS recordings), so you can ask about the
car in plain English from Claude Code, Codex or Cursor.

> You must be on the CEV Tailscale network. The curated server is at
> `http://100.122.165.58:8765/mcp` (the NUC, `cev-nuc`) and the raw-SQL server at
> `http://100.122.165.58:8767/mcp`. Both are read-only.

## Just want a browser?

Open **http://100.122.165.58:8081** (EVIL-UI). Data browser plus a chat panel. No
setup.

## Fastest setup: one command

```bash
git clone https://github.com/cornellev/evil-mcp.git && cd evil-mcp && ./install.sh
```

`install.sh` registers EVIL (`evil` and `evil-raw`) globally for whichever of Claude Code, Codex and
Cursor it finds, so it works from any project. Re-running is safe;
`./install.sh --dry-run` shows what it would do. Restart your client afterwards,
then ask: *"List the EVIL runs."*

## Only for one project

If you'd rather not have EVIL in every session (privacy, or to keep its skill out
of the way in unrelated projects), scope it to one directory:

```bash
./install.sh --project ~/path/to/your/project
```

EVIL is then on only in sessions started in that directory or any subdirectory.
It writes `.mcp.json` and `.claude/skills/evil/` there, plus `.cursor/mcp.json` and
`.codex/config.toml` if you have those clients. If the directory is a git repo,
the new files are added to `.git/info/exclude`, so they never get committed. If
your project already tracks a `.mcp.json`, the EVIL entries will show in
`git status`; the script tells you when that happens. Claude Code asks you once
to approve the project's servers the first time you start a session there.

To switch from global to project-only, remove the global install first:

```bash
./install.sh --uninstall                       # remove the global install
./install.sh --project ~/path/to/your/project  # then scope it
```

`./install.sh --uninstall --project DIR` removes it from a project. Neither form
touches other servers in the same config files.

## Updating

| What changed | What you do |
|---|---|
| Tools on the server (new tool, fixed tool, new data) | Nothing. Restart your client or start a new session and it picks up the new tool list. |
| The guidance (`AGENTS.md` / the Claude skill), or a new server or URL | `git pull && ./install.sh` in your clone (add `--project DIR` if that's how you installed), then restart your client. |

`install.sh` is both the installer and the updater. Re-running it adds any new
servers, re-points entries whose URL changed and refreshes the Claude skill. It
leaves alone anything already up to date. Codex and Cursor users who copied
`AGENTS.md` somewhere by hand need to copy it again after pulling.

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
| Claude Code | `claude mcp add --transport http --scope user evil http://100.122.165.58:8765/mcp` and `... evil-raw http://100.122.165.58:8767/mcp` |
| Codex | `codex mcp add evil --url http://100.122.165.58:8765/mcp` and `codex mcp add evil-raw --url http://100.122.165.58:8767/mcp` |
| Cursor | add `"evil": {"url": ".../8765/mcp"}` and `"evil-raw": {"url": ".../8767/mcp"}` under `mcpServers` in `~/.cursor/mcp.json` |

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
- "Where is the raw recording covering Turn 7?"
- "What recordings do we have from last weekend, and which ones didn't parse?"
- "(raw) What topics are in that bag, and how many messages on each?"

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

- `evil-raw` is a separate server on purpose: it gives free-form SQL over stored files, so it
  is kept off the port the web UI and the in-app assistant use. Everything that comes back
  from a recording file is untrusted data (the guidance in `AGENTS.md` says so).
- Verified against a real server: the endpoint and the original nine tools respond. The
  Claude Code setup is tested by the author. The Codex and Cursor configs follow
  those clients' current documentation but have not been run end to end; fix the
  file and open a PR if one is off.
- Only the two read ports (`:8765` curated, `:8767` raw SQL) are wired up here. EVIL's
  separate upload port is not part of this repo.
- Guidance lives once, in `AGENTS.md`. After editing it, run
  `scripts/sync-skill.sh` to regenerate the Claude skill
  (`scripts/sync-skill.sh --check` fails if they have drifted). Then commit and tell
  the team to run `git pull && ./install.sh`. Server-side tool changes need no
  announcement beyond "restart your client".
