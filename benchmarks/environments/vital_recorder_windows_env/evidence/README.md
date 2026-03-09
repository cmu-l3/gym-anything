# Vital Recorder Windows Environment - Evidence Documentation

## Environment Overview

| Field | Value |
|-------|-------|
| **Environment ID** | `vital_recorder_windows_env@0.1` |
| **Application** | Vital Recorder 1.16.6 (VitalDB, Seoul National University Hospital) |
| **OS** | Windows 11 (QEMU/Apptainer) |
| **Resolution** | 1280x720 |
| **Resources** | 4 CPU, 8GB RAM, no GPU |
| **Data Source** | VitalDB Open Dataset (real surgical case recordings) |
| **Tasks** | 5 tasks (2 easy, 3 medium) |

## Final Test Results (Phase 7)

Clean test run on 2026-02-17 with `use_cache=False` (all hooks executed from scratch).

### Timing

| Phase | Duration |
|-------|----------|
| Full environment setup (pre_start + post_start) | 137.7s |
| Pre-task hook (per task) | ~35-38s |
| Total (fresh boot to task ready) | ~172s |
| Cached boot (post_start checkpoint + pre_task) | ~127-144s |

---

## Verification Checklist

### Installation (pre_start hook)

- [x] **Installation script completes without errors**
  - MSI download: 6.9 MB from `vitaldb.net/getvr.php?type=msi&ver=1.16.6`
  - Step 1 (initial MSI install): exit code 0
  - Step 2 (REINSTALL=ALL REINSTALLMODE=omus): exit code 0
  - Verified: `C:\Users\Docker\AppData\Roaming\VitalRecorder\Vital.exe` exists
  - 3 .vital data files copied to Desktop
  - See: `pre_start_hook.log`

**Log snippet (pre_start):**
```
=== Installing Vital Recorder ===
Downloading Vital Recorder MSI installer...
Downloaded MSI: 6.9 MB
Step 1: Initial MSI install...
MSI initial install exit code: 0
Step 2: Forcing full file extraction (REINSTALL=ALL)...
MSI reinstall exit code: 0
Vital Recorder installed successfully at: C:\Users\Docker\AppData\Roaming\VitalRecorder\Vital.exe
Copying vital data files to Desktop...
Copied 3 .vital files to C:\Users\Docker\Desktop\VitalRecorderData
=== Vital Recorder installation complete ===
```

### Configuration (post_start hook)

- [x] **Setup script completes without errors**
  - OneDrive disabled
  - Windows consumer features disabled
  - 3 .vital data files confirmed in data directory
  - Warm-up launch completed (schtasks /IT pattern)
  - Dialog dismissal script ran
  - Application killed after warm-up
  - Command windows hidden
  - See: `post_start_hook.log`

**Log snippet (post_start):**
```
=== Setting up Vital Recorder ===
Step 1: Disabling OneDrive...
OneDrive disabled.
Step 2: Disabling Windows consumer features...
Step 3: Ensuring vital data files are available...
Data directory has 3 .vital files
Step 4: Warm-up launch of Vital Recorder...
Vital Recorder executable: C:\Users\Docker\AppData\Roaming\VitalRecorder\Vital.exe
[...schtasks messages...]
Killing Vital Recorder after warm-up...
Step 5: Hiding command windows...
=== Vital Recorder setup complete ===
```

### Application State

- [x] **Application is visible in screenshot** (all 5 task screenshots confirm this)
- [x] **Application is in correct initial state with real data loaded** (verified per task below)
- [x] **No first-run dialogs** (warm-up launch in post_start clears any)

---

## Task Start State Verification

Each task was tested with `use_cache=True, cache_level="post_start", use_savevm=True` and verified via VNC screenshot + visual_grounding MCP tool.

### Task 1: open_vital_file (easy)

- **Screenshot**: `task_open_vital_file.png`
- **Start state**: Vital Recorder open with empty workspace showing "Open File or Add Device" prompt
- **Data**: `0001.vital` (21MB, 3h 12m real intraoperative case from VitalDB) pre-placed at `C:\Users\Docker\Desktop\VitalRecorderData\`
- **Agent goal**: Open the file using the folder icon (2nd toolbar button)
- [x] Application visible and in correct state
- [x] Empty workspace confirmed (no file loaded)
- [x] Data file present on Desktop
- [x] Toolbar icons visible for agent interaction

### Task 2: export_to_csv (medium)

- **Screenshot**: `task_export_to_csv.png`
- **Start state**: Vital Recorder with `0002.vital` loaded, showing 4h 22m 20s of data with ECG_II, ECG_V5, PLETH, HR, ST_V5, PLETH_SPO2, PLETH_HR, VENT_RR, VENT_MV tracks
- **Data**: `0002.vital` (21MB real surgical case) pre-loaded
- **Agent goal**: Export to CSV using 5th toolbar icon, save as `case_0002_export.csv` on Desktop
- [x] File loaded and tracks visible
- [x] Events panel shows 4 events (Case started, Surgery started, Surgery finished, Case finished)
- [x] Export icon visible in toolbar (5th from left)
- [x] Any previous export file removed

### Task 3: switch_monitor_mode (easy)

- **Screenshot**: `task_switch_monitor_mode.png`
- **Start state**: Vital Recorder with `0001.vital` loaded in Track mode, showing ART (red), ECG_II, ECG_V5 (green), PLETH (blue), CO2 (yellow), AWP tracks
- **Data**: `0001.vital` (3h 12m 22s real surgical case) pre-loaded
- **Agent goal**: Click first toolbar icon to toggle from Track to Monitor mode
- [x] Track mode confirmed (waveform strips visible)
- [x] File loaded with real physiological data
- [x] Toggle icon visible (1st toolbar button)

### Task 4: add_event_marker (medium)

- **Screenshot**: `task_add_event_marker.png`
- **Start state**: Same as switch_monitor_mode (0001.vital loaded in Track mode)
- **Data**: `0001.vital` with pre-existing events visible in right panel
- **Agent goal**: Click "+ Add Event" button, add "Surgical Incision" event
- [x] File loaded with real data
- [x] Events panel visible with 4 pre-existing events
- [x] "+ Add Event" button visible in right panel

### Task 5: configure_track_display (medium)

- **Screenshot**: `task_configure_track_display.png`
- **Start state**: Vital Recorder with `0003.vital` loaded in Track mode, showing ECG_II, ECG_V5, PLETH, COMPLIANCE, INSP_SEVO, EXP_SEVO, PAMB_MBAR, MAWP_MBAR, PPLAT_MBAR tracks
- **Data**: `0003.vital` (6.5MB, 1h 13m 14s real surgical case) pre-loaded
- **Agent goal**: Navigate to "Surgery started" event and zoom in to 10-30 minute detail view
- [x] File loaded with real data (different case than tasks 1-4)
- [x] Events panel shows 4 events including "Surgery started"
- [x] Timeline and zoom controls visible at bottom

---

## Data Provenance

All data files are real surgical case recordings from the **VitalDB Open Dataset** (https://vitaldb.net):

| File | Source URL | Size | Duration | Tracks |
|------|-----------|------|----------|--------|
| `0001.vital` | `https://api.vitaldb.net/0001.vital` | 21MB | 3h 12m 22s | ART, ECG_II, ECG_V5, PLETH, CO2, AWP, BIS, etc. |
| `0002.vital` | `https://api.vitaldb.net/0002.vital` | 21MB | 4h 22m 20s | ECG_II, ECG_V5, PLETH, HR, ST_V5, PLETH_SPO2, VENT_RR, etc. |
| `0003.vital` | `https://api.vitaldb.net/0003.vital` | 6.5MB | 1h 13m 14s | ECG_II, ECG_V5, PLETH, COMPLIANCE, INSP_SEVO, EXP_SEVO, etc. |

VitalDB is an open-access dataset of 6,388 intraoperative vital sign cases from Seoul National University Hospital, published for anesthesia research.

---

## Evidence Files

| File | Description |
|------|-------------|
| `pre_start_hook.log` | Full transcript of installation script (pre_start hook) |
| `post_start_hook.log` | Full transcript of setup script (post_start hook) |
| `task_open_vital_file.png` | Screenshot of open_vital_file task start state |
| `task_export_to_csv.png` | Screenshot of export_to_csv task start state |
| `task_switch_monitor_mode.png` | Screenshot of switch_monitor_mode task start state |
| `task_add_event_marker.png` | Screenshot of add_event_marker task start state |
| `task_configure_track_display.png` | Screenshot of configure_track_display task start state |
