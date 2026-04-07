# Task: Timeline Maintenance Schedule

## Domain Context

Payload operations engineers are responsible for pre-planning and scheduling all routine
maintenance command sequences for spacecraft subsystems. Mission rules mandate that
maintenance procedures be scheduled in the ground system timeline tool in advance, creating
an auditable record of planned operations. The timeline system allows operators to define
named timelines containing activities — each activity specifying a start time and the
command sequence to execute.

OpenC3 COSMOS provides a Timeline tool for this purpose. Operators create named timelines,
add scheduled activities with start times and associated command sequences, then export a
confirmation record for mission planning documentation.

## Occupation

**Payload Operations Engineer** — plans and schedules spacecraft maintenance procedures
using ground control timeline management tools.

## Goal

Using the COSMOS Timeline tool, create a new timeline named `MAINT_SCHEDULE`, add a
maintenance activity scheduled at least 30 minutes in the future with a command sequence
containing at least two INST commands, and produce a confirmation report on the Desktop.

The end state is a file `/home/ga/Desktop/timeline_schedule.json` that was **created
during this session** and documents the created timeline and its scheduled activity.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Export metadata readable | 20 |
| Confirmation JSON file exists on Desktop | 10 |
| File created this session (hard gate) | 10 |
| Timeline count in COSMOS increased | 15 |
| JSON has all 4 required keys | 15 |
| `activity_start_time` is a valid datetime (year ≥ 2020) | 15 |
| `commands` array has ≥ 2 entries | 15 |
| **Total** | **100** |

**Pass threshold: 60 points**

The timeline count check (15 pts) verifies that a timeline was actually created in COSMOS,
not just documented locally. Both the COSMOS state and the file content must be consistent.

## Required Output Schema

`/home/ga/Desktop/timeline_schedule.json`:
```json
{
  "timeline_name": "<string, name of the created timeline>",
  "activity_start_time": "<ISO 8601 datetime string, at least 30 min from task start>",
  "commands": [
    "<string describing command 1>",
    "<string describing command 2>"
  ],
  "activity_description": "<string describing the maintenance purpose>"
}
```

## Verification Strategy

1. **Export metadata** (`/tmp/timeline_maintenance_schedule_result.json`) checked first;
   includes `initial_timeline_count` and `current_timeline_count` from COSMOS REST API.
2. **File freshness** checked via `file_mtime >= task_start_ts`.
3. **Timeline count increase**: `current_timeline_count > initial_timeline_count`.
4. **JSON content** read from Desktop via `copy_from_env`.
5. **Required keys**: `timeline_name`, `activity_start_time`, `commands`, `activity_description`.
6. **activity_start_time**: parsed by `datetime.fromisoformat()` or `dateutil.parser.parse()`;
   year must be ≥ 2020.
7. **commands**: checked as list with ≥ 2 string entries.

## Edge Cases and Potential Issues

- The timeline must actually be created in COSMOS — the verifier checks the COSMOS REST API
  timeline count (before vs. after), not just the output file.
- `activity_start_time` must be parseable as a datetime; format is flexible but must include
  a year component ≥ 2020.
- `commands` must be a list of at least 2 string entries describing the scheduled commands.
- The agent must use the COSMOS Timeline tool — the verifier cannot tell which tool was used,
  but the timeline count check requires actual COSMOS state change.
- COSMOS password: `Cosmos2024!`
