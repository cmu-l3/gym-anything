# compare_surgical_cases

## Overview
Multi-step surgical case comparison workflow in Vital Recorder 1.16.6.
This is a **hard** task that requires opening two different VitalDB surgical
case recordings, exporting each to CSV, and authoring a structured text
comparison summarizing clinical differences between the cases.

## Domain Context
An anesthesiologist assistant is performing a retrospective case review of two
noncardiac surgery cases from the VitalDB open dataset (Seoul National
University Hospital). Each case has different monitoring configurations and
durations. The assistant must produce exportable data files and a plain-text
comparison summary for the departmental quality review meeting.

## What the Agent Must Do
1. Open `0001.vital` in Vital Recorder and export it to CSV at
   `C:\Users\Docker\Desktop\case_0001_data.csv`
2. Open `0002.vital` in Vital Recorder and export it to CSV at
   `C:\Users\Docker\Desktop\case_0002_data.csv`
3. Create a comparison summary text file at
   `C:\Users\Docker\Desktop\case_comparison.txt` documenting:
   - Recording duration of each case
   - Which physiological tracks/channels are available in each case
   - Notable differences in the surgical event timeline
     (Case started, Surgery started, Surgery finished, Case finished)

## Why This Is Hard
- Requires using multiple app features: file opening, CSV export (twice),
  text file creation
- Agent must discover how to load a second file after exporting the first
  (may need to close the first case or use File > Open again)
- Agent must analyze the actual waveform data and events to identify
  differences between cases
- Agent must create a structured, interpretive text summary -- not just
  click buttons
- No specific UI navigation steps are spelled out in the description

## Ground Truth (from real VitalDB data)

### Case 0001 (`0001.vital`)
- **Duration**: ~3h 12m 22s
- **Tracks**: ART (arterial pressure), ECG_II, ECG_V5, PLETH (pulse ox),
  CO2 (capnography), AWP (airway pressure), INSP_SEVO, EXP_SEVO
  (anesthetic agent concentrations)
- **Events**: Case started, Surgery started, Surgery finished, Case finished

### Case 0002 (`0002.vital`)
- **Duration**: ~4h 22m 20s
- **Tracks**: ECG_II, PLETH, HR (heart rate), ST_II, ST_V5 (ST segment),
  NIBP_SYS, NIBP_DIA, NIBP_MEAN (non-invasive BP), SpO2,
  ventilator parameters (VENT_TV, VENT_PEEP, VENT_RR, etc.)
- **Events**: Case started, Surgery started, Surgery finished, Case finished

### Key Differences
- Case 0002 is ~70 minutes longer
- Case 0001 has invasive arterial pressure (ART); Case 0002 uses NIBP
- Case 0001 monitors anesthetic agent (sevoflurane); Case 0002 does not
- Case 0002 has ST segment monitoring; Case 0001 does not
- Case 0002 has ventilator parameters; Case 0001 has capnography + AWP

## Pre-Task Setup (`setup_task.ps1`)
- Kills any running Vital Recorder instances
- Ensures both `0001.vital` and `0002.vital` are in `VitalRecorderData`
- Removes any previous output files (CSVs and summary)
- Records baseline state to `task_baseline_compare.json`
- Launches Vital Recorder with an empty workspace (no file pre-loaded)
- Dismisses startup dialogs
- Verifies app is running

## Post-Task Export (`export_result.ps1`)
- Checks existence and size of each CSV export
- Reads CSV headers (first line) to extract column names
- Counts total lines in each CSV
- Checks existence and content of `case_comparison.txt`
- Writes structured JSON result to `task_result_compare.json`

## Verification (`verifier.py`)
Multi-criterion scoring (100 points total, pass at 60):

| Criterion | Points | Description |
|-----------|--------|-------------|
| CSV export of case 0001 | 20 | File exists at expected path with >100 bytes |
| CSV export of case 0002 | 20 | File exists at expected path with >100 bytes |
| Comparison summary file | 20 | File exists at expected path with >200 bytes |
| Summary mentions both cases | 20 | Text contains both "0001" and "0002" identifiers |
| Summary has duration or track info | 20 | Text contains duration info or track names from real data |

**Output gate**: If no output files exist at all (no CSVs and no summary),
return score=0 immediately.

Anti-tamper: verifier independently copies files from the VM via
`copy_from_env` (does not rely solely on the export JSON).

## File Layout
```
compare_surgical_cases/
  task.json           - Task definition with hooks, metadata, scoring
  README.md           - This file
  setup_task.ps1      - Pre-task hook: launch Vital Recorder with empty workspace
  export_result.ps1   - Post-task hook: collect output files as JSON
  verifier.py         - Multi-criterion verifier (100pt scale)
```
