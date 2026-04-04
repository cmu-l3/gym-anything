# Task: icu_monitoring_setup

**Difficulty:** Hard
**Domain:** Critical Care Nursing - ICU Monitoring Setup
**Environment:** openice_env@0.1

## Clinical Context

Post-cardiac surgery patient monitoring requires simultaneous tracking of multiple physiological parameters across different domains. A critical care nurse must configure an ICU monitoring station that integrates hemodynamic monitoring, respiratory gas analysis, and additional physiological surveillance to ensure comprehensive patient safety in the immediate post-operative period.

This task simulates the real-world process of preparing a multi-device monitoring station using OpenICE (Open Integrated Clinical Environment), which enables interoperable medical device networking. The nurse must select clinically appropriate device types, confirm data flow through a clinical application, and document the monitoring configuration.

## Task Goal

Configure a complete ICU monitoring station using OpenICE by:

1. Creating **3 distinct simulated device adapters** covering different physiological domains:
   - A **Multiparameter Monitor** for primary vital signs (ECG, SpO2, hemodynamics)
   - A **CO2 or respiratory gas monitoring device** (for end-tidal CO2 and ventilation status)
   - One **additional monitoring device of choice** from available OpenICE simulated types (e.g., infusion pump, NIBP, pulse oximeter, temperature adapter, IBP)

2. Launching the **Vital Signs clinical application** and confirming that data from all three devices is actively flowing.

3. Navigating to the **device detail view** for at least one device to observe waveform and numeric parameters.

4. Writing a **pre-shift monitoring checklist** to `/home/ga/Desktop/monitoring_checklist.txt` that:
   - Lists each of the three device types configured
   - Describes the physiological parameters each device monitors
   - Includes a confirmation statement that all devices showed active data flow

## Difficulty Rationale (Hard)

The agent is told **what device types to create** and **what file to write**, but is **not told which menus or buttons to use** in the OpenICE Supervisor interface. The agent must independently discover the UI workflow for:
- Creating a new simulated device adapter
- Selecting the correct device type from available options
- Launching a specific clinical application
- Navigating to a device detail view
- Writing a structured clinical document

## Scoring (100 points total)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Multiparameter Monitor created | 10 | Detected via log entry or window title |
| CO2/respiratory device created | 10 | Detected via log entry or window title |
| Third distinct device created | 10 | Detected via log entry or window title |
| Vital Signs app launched | 15 | Detected via log entry matching vital sign app patterns |
| Device detail view opened | 15 | Detected via window count increase (>1 new window) |
| Monitoring checklist exists + written after task start | 20 | File at correct path, >= 150 bytes, mtime after task start |
| Report mentions 3+ device types | 20 | Regex matches for all three device type categories in report |

**Pass threshold:** 60 points

**GATE condition:** If fewer than 2 distinct device adapters are created AND no report file exists AND window increase < 2, score is immediately set to 0 (agent did not meaningfully attempt the task).

## Verification Strategy

### New Log Lines Only Approach
- At task start, the current log file size is recorded in `/tmp/initial_log_size`
- During export, only log lines written **after** setup are analyzed (tail from byte offset)
- This prevents false positives from pre-existing log entries

### Device Detection
Each device type is detected using two independent signals (OR logic):
- **Log pattern match**: New log entries containing device-type-specific keywords
- **Window title match**: Open windows whose titles contain device-type-specific keywords

Device-specific patterns:
- Multiparameter: `multiparameter`, `multiParam`
- CO2/respiratory: `CO2`, `carbon dioxide`, `etco2`, `capno`, `resp.*gas`, `SimCO2`
- Third device: `infusion`, `pump`, `NIBP`, `blood.*press`, `ECG`, `pulse.?ox`, `SpO2.*adapt`, `temperature`, `temp.*adapt`, `IBP`, `invasive`

### Window Count
- Initial window count recorded at setup
- Final window count checked at export
- Window increase used as proxy for: device adapter windows created, clinical app launched, detail views opened

### File Timestamp Check
- Uses `int(mtime) > task_start` (integer comparison) to determine if the report was written after task start
- Avoids floating point issues with stat output

### Report Content Analysis
- Binary grep flags (no `grep -c` with fallback) for each device type category
- Confirmation language check: `active`, `flowing`, `streaming`, `confirmed`, `running`, `connected`, `operational`

## Files

| File | Purpose |
|------|---------|
| `README.md` | This documentation file |
| `task.json` | Task definition, metadata, and scoring configuration |
| `setup_task.sh` | Pre-task hook: records baseline state (log size, window count, timestamp) |
| `export_result.sh` | Post-task hook: collects evidence and writes `/tmp/task_result.json` |
| `verifier.py` | Scoring logic: reads result JSON and computes final score |

## Example Monitoring Checklist Content

A well-formed monitoring checklist at `/home/ga/Desktop/monitoring_checklist.txt` might include:

```
POST-CARDIAC SURGERY ICU MONITORING CHECKLIST
Patient: [ID] | Date: [Date] | Nurse: [Name]

DEVICE 1: Multiparameter Monitor
- Parameters: ECG, Heart Rate, SpO2, MAP, CVP
- Status: ACTIVE - data flowing confirmed

DEVICE 2: CO2/Respiratory Gas Monitor
- Parameters: End-tidal CO2 (EtCO2), Respiratory Rate, FiO2
- Status: ACTIVE - streaming confirmed

DEVICE 3: Infusion Pump Adapter
- Parameters: Infusion rate, volume delivered, occlusion alerts
- Status: ACTIVE - connected and operational

All three devices confirmed active and streaming data through OpenICE Vital Signs application.
Pre-shift monitoring check COMPLETE.
```
