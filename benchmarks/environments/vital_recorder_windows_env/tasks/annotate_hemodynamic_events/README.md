# Annotate Hemodynamic Events Task (`annotate_hemodynamic_events@1`)

## Overview

This is a **hard** task that requires the agent to perform a retrospective clinical case review by annotating hemodynamic events in a surgical vital signs recording. The agent must navigate the arterial blood pressure (ART) waveform timeline, add multiple event markers at clinically meaningful positions, and export the annotated recording to CSV.

## Task Context

**Scenario**: An anesthesiologist assistant is performing a retrospective review of case 0001 from the VitalDB open dataset (a real noncardiac surgery recorded at Seoul National University Hospital). The ~3-hour intraoperative recording contains continuous waveforms for arterial blood pressure (ART), ECG leads (ECG_II, ECG_V5), pulse oximetry (PLETH), capnography (CO2), and airway pressure (AWP).

The recording already has four surgical milestone events:
- **Case started** - Patient arrives in OR
- **Surgery started** - Surgical incision
- **Surgery finished** - Surgical closure complete
- **Case finished** - Patient leaves OR

The agent must add at least 3 additional event markers during the intraoperative period (between Surgery started and Surgery finished) with descriptive clinical labels, then export the annotated recording to CSV.

## Why This Is Hard

1. **Timeline navigation**: The agent must scroll or navigate the timeline to specific positions along a ~3-hour recording rather than just working at the current cursor position.
2. **Multi-step event creation**: Each event requires clicking "+ Add Event", positioning the timeline cursor, and entering a descriptive label -- repeated at least 3 times.
3. **Clinical interpretation**: Event labels should reflect observable waveform patterns (blood pressure changes, heart rate variations, etc.), requiring the agent to interpret what it sees in the waveforms.
4. **Combined workflow**: The task combines timeline navigation, event annotation, CSV export via the Save As dialog, and file management -- touching multiple UI areas of Vital Recorder.
5. **Spread requirement**: Events should be placed at distinct time positions spread across the surgical period, not clustered at one point.

## Starting State

Vital Recorder 1.16.6 is open with `0001.vital` loaded in Track mode. The track window displays:
- **ART** (red waveform) - Arterial blood pressure
- **ECG_II / ECG_V5** (green waveforms) - Electrocardiogram leads
- **PLETH** (light blue waveform) - Pulse oximetry plethysmograph
- **CO2** (yellow waveform) - Capnography
- **AWP** (white waveform) - Airway pressure

The right panel shows the 4 existing surgical events with timestamps, and the "+ Add Event" and "Preset" buttons above the event list. The EVENTS bar on the timeline shows the existing event markers.

## Agent Steps

1. Navigate the timeline to a position during the surgical period (between Surgery started and Surgery finished).
2. Click "+ Add Event" to add a new event marker at that position.
3. Enter a descriptive clinical label (e.g., "Blood pressure drop observed", "Hemodynamic stabilization", "Vasopressor administration suspected").
4. Repeat steps 1-3 at least two more times at different timeline positions.
5. Export the recording to CSV: click the export toolbar icon (5th from left), navigate to Desktop in the Save As dialog, name the file `annotated_0001.csv`, and save.

## Verification Criteria (100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| At least 1 new event | 25 | The .vital file contains more than the initial 4 events |
| At least 3 new events | 25 | The .vital file contains at least 7 total events (4 original + 3 new) |
| CSV export exists | 20 | `C:\Users\Docker\Desktop\annotated_0001.csv` exists and is >100 bytes |
| Events have text labels | 15 | New event markers have non-empty descriptive text labels |
| CSV has vital signs columns | 15 | The CSV header contains recognizable vital signs column names (ART, ECG, PLETH, CO2, AWP, etc.) |

**Output gate**: If no new events were added AND no CSV file exists, score is 0.

**Pass threshold**: 60/100

## File Inventory

| File | Purpose |
|------|---------|
| `task.json` | Task definition with hooks, metadata, and success criteria |
| `setup_task.ps1` | Pre-task hook: launches Vital Recorder with 0001.vital, records baseline event count |
| `export_result.ps1` | Post-task hook: captures screenshot, checks CSV, writes result JSON |
| `verifier.py` | Programmatic verifier using `copy_from_env` to independently verify results |
| `README.md` | This documentation file |
