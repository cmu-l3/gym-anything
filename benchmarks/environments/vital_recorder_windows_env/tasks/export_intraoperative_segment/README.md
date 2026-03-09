# Task: export_intraoperative_segment

## Overview

With case `0001.vital` loaded in Vital Recorder (showing the full 3h 12m recording), the agent must navigate to the "Surgery started" event on the timeline, zoom into the surgical period, export ONLY the intraoperative segment (from "Surgery started" to "Surgery finished") as a CSV file, and verify the exported data covers the correct time window.

## Difficulty: HARD

## Why This Is Hard

- Agent must navigate the timeline to specific event markers ("Surgery started" at ~00:27:48, "Surgery finished" at ~02:52:48)
- Agent must figure out how to select/export only a segment (not the full recording) -- Vital Recorder supports this but the method is not spelled out in the task description
- Agent needs to work with timeline controls, zoom, and the export feature in combination
- Requires understanding of what "intraoperative" means clinically (surgery start to surgery finish, excluding pre/post-operative periods)

## Starting State

Vital Recorder open with `0001.vital` loaded in Track mode showing the full recording timeline. The events panel on the right shows four surgical milestones: Case started, Surgery started, Surgery finished, and Case finished.

## What the Agent Must Do

1. Identify the "Surgery started" and "Surgery finished" events in the event list
2. Navigate the timeline to the intraoperative period
3. Select/mark the segment from Surgery started (~00:27:48) to Surgery finished (~02:52:48)
4. Export only that selected segment as CSV
5. Save the exported file as `C:\Users\Docker\Desktop\intraop_0001.csv`

## Verification (5 criteria, 100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| 1 | 25 | CSV export file exists at `C:\Users\Docker\Desktop\intraop_0001.csv` with >100 bytes |
| 2 | 25 | CSV contains physiological data columns (ART, ECG, PLETH, etc.) |
| 3 | 20 | CSV data represents the intraoperative period -- not the full recording (row count significantly less than full-case export) |
| 4 | 15 | CSV has header row with recognizable vital signs track names |
| 5 | 15 | File was created after the task started (timestamp check) |

**Output gate:** If no CSV file exists, return score=0 immediately.

## Key Metadata

- Case file: `0001.vital`
- Case duration: 3h 12m 22s (~11,542 seconds)
- Surgery started: ~00:27:48 (1,668 seconds)
- Surgery finished: ~02:52:48 (10,368 seconds)
- Intraoperative duration: ~145 minutes (~8,700 seconds)
- Expected intraoperative row count: roughly 60-80% of total recording rows

## Files

- `task.json` -- Task definition with hooks, metadata, and success criteria
- `setup_task.ps1` -- Pre-task setup: launches Vital Recorder with 0001.vital, records baseline timestamp
- `export_result.ps1` -- Post-task export: reads CSV properties and writes result JSON for verifier
- `verifier.py` -- Programmatic multi-criterion verifier using copy_from_env
