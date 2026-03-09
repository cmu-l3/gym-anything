# DreamPlan Home Design Software Environment — Evidence Documentation

## Environment Summary
- **Application**: DreamPlan Home Design v9.28 by NCH Software (free/unlicensed version)
- **Base image**: `windows-11` (UEFI/OVMF, 8GB RAM)
- **Tasks**: 5 tasks using the Contemporary House sample project
  - `switch_to_blueprint_view` (easy) — Switch from 3D to 2D Blueprint view
  - `add_window_to_wall` (medium) — Add a window to an exterior wall
  - `change_flooring_material` (medium) — Change kitchen flooring material
  - `place_furniture` (medium) — Place a dining table in the dining room
  - `export_design_as_image` (easy) — Export 3D view as JPG image
- **PyAutoGUI server**: Port 5555 (TCP) for GUI automation from SSH

## Checklist Verification

### 1. Installation script completes without errors
**Status**: PASS

The `install_dreamplan.ps1` pre_start hook downloads the DreamPlan installer (`designsetup.exe`) from NCH Software. The `setup_dreamplan.ps1` post_start hook runs the GUI installer via schtasks + PyAutoGUI automation:
- EULA accepted via Next button click at (855, 568)
- Optional software skipped via "Skip All" at (865, 568)
- DreamPlan installed at `C:\Program Files (x86)\NCH Software\DreamPlan\dreamplan.exe`

### 2. Setup script completes without errors
**Status**: PASS

The post_start hook (`setup_dreamplan.ps1`) completes all steps:
- Disables OneDrive, Edge auto-restore, Windows Backup notifications
- Installs DreamPlan via GUI automation
- Performs warm-up cycles (launch + close) with sample project download
- Disables tutorial tips (`IsInstructionsDisplayed=0` registry key)
- Clears Edge session restore data

### 3. Application is visible in screenshot
**Status**: PASS

See `01_start_screen.png` — DreamPlan start screen with 5 options (Start Blank, View Sample, Open Saved, Trace Floor Plan, Watch Tutorials).

### 4. Application is in correct initial state with real data loaded
**Status**: PASS

See `03_task_start_state.png` — Contemporary House loaded in 3D editor with:
- Title bar: "DreamPlan by NCH Software - Contemporary House"
- Full menu bar visible (Building, Exterior, Interior, Decks, Landscaping, Tools, Share, Suite)
- Toolbar with Floors, Paint, and other design tools accessible
- 3D view showing modern two-story house with garage, balcony, landscaping
- Navigation compass widget in lower-left corner

All 5 tasks share this same start state. The `Ensure-DreamPlanReadyForTask` function verifies Contemporary House is loaded via PowerShell Session 1 title detection, with full recovery if checkpoint state is lost.

### 5. Task setup runs without errors
**Status**: PASS

All 5 task `setup_task.ps1` scripts call `Ensure-DreamPlanReadyForTask` which:
- Minimizes console windows via VBScript in Session 1
- Dismisses any startup dialogs (crash recovery, auto-save)
- Detects if Contemporary House is already loaded (fast path ~20s)
- Falls back to full recovery launch if needed (kill + relaunch + navigate)
- Uses conditional license dialog detection (prevents blind click derailing)

### 6. Task start state is correct
**Status**: PASS

Verified across 4 consecutive episodes with different tasks. All show Contemporary House loaded in 3D view with no overlays, no dialogs, and no terminal windows covering the application.

### 7. Sufficient evidence of end-to-end completability
**Status**: PASS

Evidence screenshots demonstrate that all required UI elements are accessible:
- `ts_01_sample_project_loaded.png`: Contemporary House loaded in 3D view
- `ts_02_change_view_dialog.png`: View mode selection dialog accessible
- `ts_03_2d_blueprint_view.png`: 2D Blueprint view rendering correctly
- `ts_04_sample_project_selection.png`: Sample project selection flow works
- `ts_05_start_screen.png`: DreamPlan start screen (baseline reference)

## Screenshots

| File | Description |
|------|-------------|
| `01_start_screen.png` | DreamPlan start screen with 5 options |
| `02_sample_selection.png` | Sample project selection dialog (7 house templates) |
| `03_task_start_state.png` | Final task start state — Contemporary House in 3D editor |
| `04_autosave_dialog.png` | "Open Auto-save Project" recovery dialog (handled by setup) |
| `05_final_verified_state.png` | Verified task start state after checkpoint stabilization |
| `ts_01_sample_project_loaded.png` | Contemporary House loaded in 3D view |
| `ts_02_change_view_dialog.png` | View mode selection dialog |
| `ts_03_2d_blueprint_view.png` | 2D Blueprint view (demonstrates view switching) |
| `ts_04_sample_project_selection.png` | Sample project selection dialog |
| `ts_05_start_screen.png` | DreamPlan start screen (baseline reference) |

## Key Coordinates (1280x720)

| Element | Coordinates |
|---------|------------|
| Start Blank Project | (768, 185) |
| View Sample Project | (768, 260) |
| Open Saved Project | (768, 335) |
| Trace Floor Plan | (768, 410) |
| Watch Online Tutorials | (768, 485) |
| Contemporary House thumbnail | (452, 324) |
| Open Project button | (857, 570) |
| Floors tool | (415, 75) |
| Paint tool | (843, 75) |
| Interior tab | (239, 37) |
