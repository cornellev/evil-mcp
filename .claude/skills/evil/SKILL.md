---
name: evil
description: Query Cornell Electric Vehicles' EVIL telemetry database (runs, turns, laps, straights, energy, NAS recordings) through the `evil` MCP server. Use for any question about recorded car runs, turn or lap performance, or finding raw recordings.
---

# EVIL: how to answer questions with it

EVIL (Electric Vehicle Intelligence Layer) is Cornell Electric Vehicles' telemetry
database. It is connected to you as the `evil` MCP server. It is **read-only**:
you can query it, you cannot change it.

Use it for anything about the car's recorded runs: how a turn went, how laps
compare, energy use, speed, where a recording is stored. Do not guess at
telemetry values. If a tool did not return it, say so.

## Data model

- **run**: one recording session, identified by a `run_id` string. Always call
  `list_runs` first if you don't already have a `run_id`; never invent one.
- **turn**: one pass through a named turn (`Turn 1` ... `Turn 14` at the IMS road
  course). Detected by a circular GPS geofence (center + radius) per turn. A turn
  can occur many times in a run, once per lap. Each instance has `start_ts`,
  `end_ts`, `entry_speed` and `exit_speed`.
- **lap**: one trip around the track, numbered from 1 within a run, closed
  when the car re-enters the start/finish geofence. Has `turn_count`, `energy_wh`
  and `avg_speed`.
- **straight**: the stretch between one turn's end and the next turn's start.
  Has `entry_speed`, `exit_speed`, `avg_speed`, `energy_wh`.
- **raw samples**: `main_snapshot` ties together one tick of `gps`, `joulemeter`
  (voltage, current) and `local_planner` (target speed, planned path).
- **NAS files**: raw autonomy recordings (bag/video/lidar) stored on the NAS,
  indexed by run and time range.

Timestamps (`ts`, `start_ts`, `end_ts`, `global_ts`) are floating-point seconds.
Do not assume speed units. Report speeds as the raw numbers the tools return and
say the unit is unconfirmed unless the user tells you.

## Tools: which to use when

| Question | Tool |
|---|---|
| What runs exist? | `list_runs` |
| What turns / laps / straights are in a run? | `list_turns`, `list_laps`, `list_straights` (paginated: `limit`, `offset`) |
| How was one turn? | `get_turn(run_id, turn_name, occurrence)`: `occurrence="latest"` (default) or `"first"` |
| What could be better in a turn? | `compare_turn_instances(run_id, turn_name)`: every attempt side by side, plus the best exit speed |
| How do two laps differ? | `compare_laps(run_id, lap_a, lap_b)`: duration, energy, average speed deltas (lap B minus lap A) |
| Where is the raw footage/bag for this moment? | `find_nas_files(run_id, start_ts, end_ts)`: pass a turn's `start_ts`/`end_ts` to get the recording that covers it |
| Anything else | `read_only_sql` |

`turn_name` is forgiving: `"3"` resolves to `"Turn 3"`. Unmatched names return
`found: false` (or empty instances), which usually means a typo or that the
track geometry hasn't been loaded, not that the car skipped the turn.

`find_nas_files` returns file paths only. You cannot open or read those files
through EVIL; tell the user where they are.

## read_only_sql rules

- One `SELECT` (or `WITH ... SELECT`) statement. No semicolons mid-query.
- Capped at 200 rows and a compute budget. Aggregate (`AVG`, `COUNT`, `GROUP BY`)
  rather than pulling raw rows, and filter by `run_id` first.
- A blocklist rejects the words `insert update delete drop alter attach pragma
  vacuum` anywhere in the text, including inside string literals. Avoid them.
- Prefer the dedicated tools when one fits; use SQL for custom aggregations.

Tables and key columns:

```
main_snapshot(seq, run_id, global_ts, joulemeter_id, planner_id, gps_id)
gps(id, ts, lat, lon, speed, heading)
joulemeter(id, ts, voltage, current)
local_planner(id, ts, planned_path, target_speed)
track_geometry(turn_def_id, turn_name, center_lat, center_lon, radius_m)
turns(turn_id, run_id, turn_def_id, start_seq, end_seq, start_ts, end_ts, entry_speed, exit_speed)
laps(lap_id, run_id, lap_number, start_seq, end_seq, start_ts, end_ts, turn_count, energy_wh, avg_speed)
straights(straight_id, run_id, start_seq, end_seq, start_ts, end_ts, entry_speed, exit_speed, avg_speed, energy_wh)
start_finish_line(line_id, center_lat, center_lon, radius_m)
nas_index(file_id, run_id, path, kind, start_ts, end_ts)
```

Join `turns` to `track_geometry` on `turn_def_id` to get `turn_name`. Raw tables
are joined through `main_snapshot`.

## Answering well

- State which `run_id`, turn and attempt a number comes from.
- For "what could be improved", compare across attempts or laps and point at the
  specific difference (for example entry speed up but exit speed down) rather
  than giving generic driving advice.
- If a tool errors or returns nothing, report that plainly. Do not fill the gap
  with plausible numbers. If `list_runs` itself errors, the server's reference
  data may not be loaded yet; tell the user to ask the EVIL maintainers.
- Never try to write, ingest or delete data. EVIL's MCP has no write tools.
