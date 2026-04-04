# configure_multicase_review

## Overview
Multi-step intraoperative case review workflow in Vital Recorder 1.16.6.
This is a **hard** task that requires exporting a loaded surgical case to CSV
with anesthetic monitoring data, switching to Monitor mode, and capturing a
screenshot of the numeric vital signs display.

## Domain Context
An anesthesiologist is performing a quality-assurance review of case 0003
from the VitalDB open dataset (Seoul National University Hospital). The case
is a ~1-hour 13-minute noncardiac surgery with ventilator and anesthetic
agent monitoring tracks. The reviewer must produce an exported CSV data file
for quantitative analysis and a Monitor-mode screenshot showing the numeric
vital signs display.

## What the Agent Must Do
1. Export the loaded vital signs data from case 0003.vital to CSV format,
   saved as `C:\Users\Docker\Desktop\case_0003_review.csv`. The CSV should
   contain anesthetic monitoring tracks (INSP_SEVO, EXP_SEVO, COMPLIANCE,
   etc.).
2. Switch the display from Track mode to Monitor mode (which shows numeric
   vital signs values in large-format panels, similar to a bedside patient
   monitor).
3. Capture a screenshot of the Monitor mode display and save it as
   `C:\Users\Docker\Desktop\monitor_view_0003.png`.

## Why This Is Hard
- Requires loading a specific file and understanding its track layout
- Must navigate the Vital Recorder UI to find the CSV export function
- Must switch between Track mode and Monitor mode
- Must export CSV AND capture a screenshot -- two different output types
- Must use multiple distinct features: CSV export, display mode toggle,
  screenshot capture
- No specific UI navigation steps are spelled out in the description

## Ground Truth (from real VitalDB data)

### Case 0003 (`0003.vital`)
- **Duration**: ~1h 13m 14s
- **Tracks**: ECG_II, ECG_V5, PLETH (pulse ox), COMPLIANCE (lung compliance),
  INSP_SEVO, EXP_SEVO (sevoflurane concentrations), PAMB_MBAR, MAWP_MBAR,
  PPLAT_MBAR (airway pressures)
- **Events**: Case started, Surgery started, Surgery finished, Case finished

## Pre-Task Setup (`setup_task.ps1`)
- Kills any running Vital Recorder instances
- Ensures `0003.vital` is in `VitalRecorderData`
- Removes any previous output files (CSV and screenshot)
- Records baseline state to `task_baseline_multicase.json`
- Launches Vital Recorder with 0003.vital pre-loaded in Track mode
- Dismisses startup dialogs
- Verifies app is running

## Post-Task Export (`export_result.ps1`)
- Checks existence and size of the CSV export file
- Reads CSV header (first line) to extract column names
- Counts total lines in the CSV
- Checks existence and size of the monitor screenshot
- Writes structured JSON result to `task_result_multicase.json`

## Verification (`verifier.py`)
Multi-criterion scoring (100 points total, pass at 60):

| Criterion | Points | Description |
|-----------|--------|-------------|
| CSV file exists | 20 | File at expected path with >100 bytes |
| CSV has anesthetic columns | 20 | Header contains INSP_SEVO, EXP_SEVO, or COMPLIANCE |
| Screenshot exists | 20 | PNG file at expected path with >10 KB |
| CSV has valid header | 20 | First row contains recognizable track names |
| CSV has substantial data | 20 | More than 50 data rows |

**Output gate**: If neither CSV nor screenshot exists, return score=0
immediately.

Anti-tamper: verifier independently copies files from the VM via
`copy_from_env` (does not rely solely on the export JSON).

## File Layout
```
configure_multicase_review/
  task.json           - Task definition with hooks, metadata, scoring
  README.md           - This file
  setup_task.ps1      - Pre-task hook: launch Vital Recorder with 0003.vital
  export_result.ps1   - Post-task hook: collect output files as JSON
  verifier.py         - Multi-criterion verifier (100pt scale)
```
