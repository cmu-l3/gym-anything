# eQUEST Environment Evidence Documentation

## Environment Overview

- **Application**: eQUEST 3.65 build 7175 (DOE-2.2 building energy simulation)
- **Base image**: `windows-11` (Windows 11 QEMU VM)
- **Resources**: 4 CPU, 8 GB RAM, network enabled
- **Data**: Real building energy models from DOE-2 training workbook examples

## Verification Checklist

### Installation (pre_start hook)
- [x] eQUEST MSI downloaded from `doe2.com` (official source)
- [x] Installed to `C:\Program Files (x86)\eQUEST 3-65-7175\`
- [x] Training examples downloaded and extracted
- [x] Installation idempotent (skips if already installed)

**Log snippet** (from `env_setup_pre_start.log` on first run):
```
=== Installing eQUEST 3.65 ===
Downloading eQUEST 3.65 from doe2.com...
Download attempt 1 of 3...
Downloaded: 106.4 MB
Extracting eQUEST archive...
Found MSI: C:\eQUEST_Install\extracted\eQUEST 3-65-7175\eQUEST 3-65-7175.msi
Installing eQUEST via MSI (this may take several minutes)...
MSI installer exited with code: 0
eQUEST installed successfully at: C:\Program Files (x86)\eQUEST 3-65-7175
=== eQUEST installation complete ===
```

### Setup (post_start hook)
- [x] Building model `.inp` files copied to `C:\Users\Docker\Desktop\eQUEST_Projects\`
- [x] `eQUEST.ini` configured with registration code and data/project paths
- [x] eQUEST warm-up cycle completed (first-run registration)
- [x] Windows notifications suppressed (prevent GUI interference)
- [x] Terminal windows minimized

**Log output** (from `env_setup_post_start.log`):
```
=== Setting up eQUEST environment ===
Building model files copied to: C:\Users\Docker\Desktop\eQUEST_Projects
eQUEST executable found at: C:\Program Files (x86)\eQUEST 3-65-7175\eQUEST.exe
eQUEST.ini configured at: C:\Program Files (x86)\eQUEST 3-65-7175\eQUEST.ini
Warming up eQUEST (first-run cycle)...
eQUEST warm-up complete.
Available building model files in C:\Users\Docker\Desktop\eQUEST_Projects :
  - 4StoreyBuilding.inp
  - L_Shape.inp
  - ReaganBuilding_Calibrated.inp
=== eQUEST environment setup complete ===
```

### Task Start States
- [x] `modify_wall_absorptance`: 4StoreyBuilding.inp imported via BDL import, eQUEST open with project loaded (screenshot 03)
- [x] `run_simulation`: 4StoreyBuilding.inp imported via BDL import, eQUEST open with project loaded (same model as modify_wall_absorptance)
- [x] `change_thermostat_setpoints`: L_Shape.inp imported via BDL import, eQUEST open with project loaded (screenshot 05)
- [x] All task setup scripts navigate startup dialogs via PyAutoGUI automation
- [x] Registration values restored before each launch (prevents "Invalid PreviousRunDate" error)
- [x] Setup scripts poll for eQUEST responsiveness after BDL import (90-120s import + 120-180s polling)

**Task setup log snippet** (from `task_pre_task_change_thermostat_setpoints`):
```
=== Setting up change_thermostat_setpoints task ===
Building model: C:\Users\Docker\Desktop\eQUEST_Projects\L_Shape.inp
Registration restored in data dir INI.
Registration restored in install dir INI.
Navigating startup dialog...
BDL import started, waiting for completion...
eQUEST running (PID: 6132)
=== change_thermostat_setpoints task setup complete ===
```

### Real Data Verification
- [x] 4StoreyBuilding.inp: 3,258-line real multi-storey commercial building model (94,825 bytes)
  - 4 floors, multiple thermal zones, Stucco/Insulation Board/Gypsum Board exterior walls
  - `ABSORPTANCE = 0.6` on "EWall Construction" (line 82 — target of modify_wall_absorptance task)
- [x] L_Shape.inp: 4,476-line real L-shaped commercial building model (129,356 bytes)
  - 4 floors (Basement BB, Ground G, Middle M, Top T), 25 PSZ HVAC systems
  - First system: `"Sys1 (PSZ) (BB.C1)"` with zone `"South Perim Zn (BB.S1)"`, `DESIGN-COOL-T = 75`
- [x] ReaganBuilding_Calibrated.inp: 8,883-line real calibrated building model (292,676 bytes) — available but too large for reliable import
- [x] All models sourced from official eQUEST training workbook examples (`doe2.com`)

## Screenshots

### 01_startup_dialog.png
eQUEST Startup Options dialog showing version "eQUEST 3.65 build 7175, DOE2 Version = DOE 2.2" with radio buttons: Open Recent Project, Select an Existing Project to Open, Create a New Project via the Wizard, Generate SkyCalc Weather File. This dialog appears on every launch and is navigated by the setup_task.ps1 scripts.

### 02_file_browser_bdl_import.png
Windows file browser opened from eQUEST's "Select Existing Project" option, showing the eQUEST 3-65 Projects directory with T2408 Samples folder. The setup scripts type the .inp file path directly into the File name field and press Enter to trigger BDL import.

### 03_4StoreyBuilding_loaded.png
eQUEST with 4StoreyBuilding.pd2 successfully loaded and responsive. Title bar shows "4StoreyBuilding.pd2:1 - eQUEST Quick Energy Simulation Tool 3.65" (no "Not Responding"). The Detailed Interface toolbar shows: Project & Site, Building Shell, Internal Loads, Water-Side HVAC, Air-Side HVAC, Utility & Economics. Left panel shows Actions panel with "Simulate Building Performance" and "Review Simulation Results View" visible. Component Tree tab available at bottom left. Status bar shows "Done". This is the task start state for `modify_wall_absorptance` and `run_simulation`.

### 04_large_model_hangs_evidence.png
Evidence of the ReaganBuilding_Calibrated model (8,883 lines) causing eQUEST to become permanently "(Not Responding)" during BDL import. Title bar shows "ReaganBuilding_Calibrated.pd2:1 - eQUEST Quick Energy Simulation Tool 3.65 (Not Responding)". This is why the smaller 4StoreyBuilding (3,258 lines) and L_Shape (4,476 lines) models were chosen instead.

### 05_L_Shape_task_start_state.png
eQUEST with L_Shape.pd2 successfully loaded. Title bar shows "L_Shape.pd2:1 - eQUEST Quick Energy Simulation Tool 3.65". Same Detailed Interface layout as 4StoreyBuilding. This is the task start state for `change_thermostat_setpoints`. The L_Shape model contains 25 PSZ HVAC systems across 4 floors — the agent navigates to `Sys1 (PSZ) (BB.C1)` and its zone `South Perim Zn (BB.S1)` to change `DESIGN-COOL-T` from 75 to 76.

## Known Limitations

### Building Shell / Component Tree View Processing
Clicking the "Building Shell" toolbar button or switching to "Component Tree" tab after model import triggers heavy internal data processing in eQUEST. This causes a temporary "(Not Responding)" state that can last 30-120+ seconds depending on model size. The agent must be prepared to wait for this processing to complete before interacting with the interface.

### Model Size Constraints
- Models under ~5,000 lines (4StoreyBuilding, L_Shape): Import successfully, become responsive after processing
- Models over ~8,000 lines (ReaganBuilding): Import causes permanent hang; should not be used

### Registration Corruption
eQUEST corrupts the `[Registration]` section (Status/Special fields) in its INI file on every run. The `Restore-EqRegistration` function in `task_utils.ps1` rewrites the correct values before each launch.

## Task Completability Evidence

### modify_wall_absorptance
The agent starts with 4StoreyBuilding loaded (screenshot 03). The agent needs to:
1. Click "Building Shell" in the toolbar (wait for processing to complete)
2. Select the "Component Tree" tab at bottom left
3. Expand "Construction" section and select "EWall Construction"
4. Find the ABSORPTANCE field (currently 0.6) in the properties panel
5. Change it to 0.5
6. Save the project (File > Save or Ctrl+S)

The 4StoreyBuilding.inp confirms `ABSORPTANCE = 0.6` on "EWall Construction" (line 82), with layers of Stucco, Insulation Board, and Gypsum Board.

### run_simulation
The agent starts with 4StoreyBuilding loaded (screenshot 03). The agent needs to:
1. Click "Simulate Building Performance" in the Actions panel (visible in left panel)
2. Wait for the DOE-2.2 simulation to complete (30-60 seconds)
3. Click "Review Simulation Results View" to see energy consumption by end use

Both action items ("Simulate Building Performance" and "Review Simulation Results View") are visible in the Actions panel in screenshot 03.

### change_thermostat_setpoints
The agent starts with L_Shape loaded (screenshot 05). The agent needs to:
1. Click "Air-Side HVAC" in the toolbar (wait for processing)
2. Select "Component Tree" tab and expand HVAC systems
3. Find "Sys1 (PSZ) (BB.C1)" and its control zone "South Perim Zn (BB.S1)"
4. Change DESIGN-COOL-T from 75 to 76
5. Save the project

The L_Shape.inp confirms first system is `"Sys1 (PSZ) (BB.C1)"` (line 3277) with zone `"South Perim Zn (BB.S1)"` having `DESIGN-COOL-T = 75` (line 3307).
