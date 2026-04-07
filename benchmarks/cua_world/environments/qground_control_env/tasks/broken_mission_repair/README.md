# broken_mission_repair

**Difficulty**: hard
**Environment**: qground_control_env
**Primary Occupation**: UAV Maintenance Technician / Mission Planner

## Task Overview

A UAV Maintenance Technician must repair a corrupted QGC mission file before a survey flight. The file has 4 known critical errors: 2 waypoints at dangerously low altitude (5 m), 1 waypoint at extreme altitude (350 m), and a missing RTL command at the end. The agent loads the file in QGC, fixes all errors, and saves the corrected version under a new filename.

## Domain Context

Mission file corruption is a real hazard in UAV operations — files can be corrupted during transfer, edited accidentally, or have values changed by buggy ground station versions. A maintenance technician's job is to review missions before flight, identify any altitude anomalies or missing return commands, and certify the file is safe. Flying a mission with 5m waypoint altitudes would crash the vehicle; flying without an RTL would leave the vehicle hovering at the last waypoint until the battery depletes.

## Goal (End State)

A repaired plan file at `/home/ga/Documents/QGC/fixed_mission.plan` where:
- All navigation waypoints have altitudes in the range 40–60 m (target: 50 m)
- An RTL command (command=20) is present at or near the end of the mission

The original file `/home/ga/Documents/QGC/incoming_mission.plan` must NOT be overwritten.

## Broken Mission Errors (Injected by setup_task.sh)

The broken mission is derived from `data/sample_mission.plan` with these injections:

| Index | Command | Error | Correct |
|-------|---------|-------|---------|
| items[1] | NAV_WAYPOINT (16) | Altitude = 5 m | 50 m |
| items[3] | NAV_WAYPOINT (16) | Altitude = 5 m | 50 m |
| items[4] | NAV_WAYPOINT (16) | Altitude = 350 m | 50 m |
| (end) | RTL (20) | Removed | Must be re-added |

## Verification Strategy

The verifier parses the fixed `.plan` JSON:
1. **File exists** (10 pts): Fixed plan at expected path
2. **Modified during task** (10 pts): File mtime ≥ task start time
3. **items[1] altitude in [40, 60] m** (15 pts): `Altitude` field or `params[6]` in range
4. **items[3] altitude in [40, 60] m** (15 pts): Same check
5. **items[4] altitude in [40, 60] m** (15 pts): Same check
6. **RTL command present** (35 pts): Any item with `command == 20`

**Pass threshold**: 70

## Anti-Gaming Analysis

| Strategy | Score | Pass? |
|----------|-------|-------|
| Do-nothing (no file) | 0 | No |
| File saved but unedited | 20 | No |
| Fixed 3 altitudes, no RTL | 20+10+15+15+15+0 = 75 | Yes |
| Fixed all 4 errors | 100 | Yes |

Note: Fixing altitudes without RTL gives 75 pts > 70 threshold — this is intentional. The RTL is the highest-value single item (35 pts) because a missing return command is the most safety-critical error.

## Key Technical Details

- Altitude in QGC plan items: `item.Altitude` (float) AND `item.params[6]` (both must be corrected)
- RTL command ID: 20 (MAV_CMD_NAV_RETURN_TO_LAUNCH)
- The broken file is structurally valid JSON — QGC will load it without error; the agent must recognize the altitude values as wrong by domain knowledge
- `original_untouched` field in export JSON: mtime of original < task start time

## Files

- `task.json`: Task definition, 60 steps, 480s timeout
- `setup_task.sh`: Creates broken mission from sample_mission.plan (no ground-truth printing)
- `export_result.sh`: Stats fixed file, embeds plan JSON, checks original untouched
- `verifier.py`: Parses fixed plan, checks each waypoint altitude + RTL presence
