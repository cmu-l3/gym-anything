# Document Anesthetic Summary Task (`document_anesthetic_summary@1`)

## Overview

This is a **hard** task that requires the agent to review a loaded surgical vital signs recording, export the data to CSV, and author a structured anesthetic summary document. The task combines data export, clinical data interpretation, and structured document creation.

## Task Context

**Scenario**: An anesthesiologist assistant is completing post-operative documentation for case 0002 from the VitalDB open dataset (a real noncardiac surgery recorded at Seoul National University Hospital). The ~4-hour 22-minute intraoperative recording contains continuous physiological waveforms and derived parameters. The recording includes surgical milestone events with timestamps that define the surgical period.

The agent must produce two deliverables:
1. A CSV export of the complete vital signs recording
2. A structured anesthetic summary text document with clinical narrative

## Starting State

Vital Recorder 1.16.6 is open with `0002.vital` loaded in Track mode. The track window displays:
- **ECG_II / ECG_V5** (green waveforms) - Electrocardiogram leads
- **PLETH** (light blue waveform) - Pulse oximetry plethysmograph
- **HR** - Heart rate (derived)
- **ST_V5** - ST segment analysis
- **PLETH_SPO2** - Oxygen saturation
- **PLETH_HR** - Pulse-derived heart rate
- **VENT_RR** - Ventilator respiratory rate
- **VENT_MV** - Minute ventilation

The right panel shows the events panel with four surgical milestones:
- **Case started** (~00:00:00)
- **Surgery started** (~00:28:41)
- **Surgery finished** (~04:03:41)
- **Case finished** (~04:22:20)

## What the Agent Must Do

1. Review the recording data and event timeline visible in Vital Recorder.
2. Export the complete vital signs recording to CSV format, saved as `C:\Users\Docker\Desktop\case_0002_vitals.csv`.
3. Create a structured anesthetic summary document saved as `C:\Users\Docker\Desktop\anesthetic_summary_0002.txt` containing:
   - Case identification (case number 0002)
   - Total recording duration and surgical duration (derived from Surgery started to Surgery finished events)
   - List of all monitored physiological parameters
   - A brief clinical narrative summarizing the monitoring data and observations about the vital signs patterns during the case

## Why This Is Hard

1. **Data interpretation**: The agent must analyze real physiological data and interpret what the monitored parameters represent clinically.
2. **Multi-output workflow**: The agent must produce both a CSV export AND a structured text document -- two different output types requiring different UI interactions.
3. **Surgical duration derivation**: The agent must calculate or derive the surgical duration from the Surgery started and Surgery finished event timestamps, not just read a single number.
4. **Parameter identification**: The agent must identify all monitored physiological parameters from the track list and describe them in the summary.
5. **Clinical narrative**: The agent must write a coherent narrative section with continuous prose about the monitoring data -- not just transcribe UI labels or create bullet lists.
6. **Multiple app features**: Requires using Vital Recorder's data viewing, CSV export function, and creating a text file using Notepad or similar Windows tool.

## Ground Truth (from real VitalDB data)

### Case 0002 (`0002.vital`)
- **Total recording duration**: ~4h 22m 20s
- **Surgery started**: 00:28:41
- **Surgery finished**: 04:03:41
- **Surgical duration**: ~3h 35m (approximately 215 minutes)
- **Tracks**: ECG_II, ECG_V5, PLETH, HR, ST_V5, PLETH_SPO2, PLETH_HR, VENT_RR, VENT_MV
- **Events**: Case started, Surgery started, Surgery finished, Case finished

## Pre-Task Setup (`setup_task.ps1`)

- Kills any running Vital Recorder instances
- Ensures `0002.vital` is in `VitalRecorderData` directory
- Removes any previous output files (CSV and summary)
- Records baseline state to `task_baseline_summary.json`
- Launches Vital Recorder with `0002.vital` pre-loaded
- Dismisses startup dialogs
- Verifies app is running

## Post-Task Export (`export_result.ps1`)

- Checks existence and size of `case_0002_vitals.csv`
- Reads CSV header (first line) and counts total lines
- Checks existence and content of `anesthetic_summary_0002.txt`
- Writes structured JSON result to `task_result_summary.json`

## Verification Criteria (100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| CSV export exists | 20 | `C:\Users\Docker\Desktop\case_0002_vitals.csv` exists with >100 bytes |
| Summary document exists | 20 | `C:\Users\Docker\Desktop\anesthetic_summary_0002.txt` exists with >300 bytes |
| Summary mentions case and duration | 20 | Text contains case "0002" identifier and duration information |
| Summary lists parameters | 20 | Text contains at least 3 monitored physiological parameter names (ECG, PLETH, HR, SPO2, etc.) |
| Summary has narrative section | 20 | Text contains >100 characters of continuous prose (a narrative paragraph, not just lists) |

**Output gate**: If neither CSV nor summary file exists, score is 0.

Anti-tamper: verifier independently copies files from the VM via `copy_from_env` (does not rely solely on the export JSON).

## File Inventory

| File | Purpose |
|------|---------|
| `task.json` | Task definition with hooks, metadata, and success criteria |
| `setup_task.ps1` | Pre-task hook: launches Vital Recorder with 0002.vital, records baseline |
| `export_result.ps1` | Post-task hook: collects CSV info and summary content, writes result JSON |
| `verifier.py` | Programmatic verifier using `copy_from_env` to independently verify results |
| `README.md` | This documentation file |
