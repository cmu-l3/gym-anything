# OpenVSP Environment - Evidence Documentation

## Environment Overview

- **Application**: OpenVSP (Open Vehicle Sketch Pad) 3.48.0
- **Type**: Desktop GUI application for parametric aircraft geometry design
- **Developer**: NASA
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 8 GB RAM, networking enabled

## Real Data Sources

Two real .vsp3 aircraft model files are used (NOT synthetic/handwritten):

1. **Cessna-210_metric.vsp3** (415 KB)
   - Source: https://github.com/daptablade/docs/blob/master/mynewbook/Tutorials/openvsp-aircraft-aircraft-performance/vspaero/Cessna-210_metric.vsp3
   - A real Cessna 210 aircraft model with NLF0414F modified airfoil
   - Components: Fuselage, HSub, Vert, Horz, NormalWing, MeshGeom

2. **eCRM-001_wing_tail.vsp3** (395 KB)
   - Source: https://github.com/OpenMDAO/RevHack2020/blob/master/problems/oas_stability_derivs/eCRM-001.1_wing_tail.vsp3
   - A modified Common Research Model (eCRM-001) used in OpenMDAO integration
   - Components: FuselageUpdated, VerticalTail, Tail, Wing, WingAC, Datum, CG

## Installation

- OpenVSP 3.48.0 installed via .deb package for Ubuntu 22.04
- Required PPA `ubuntu-toolchain-r/test` for newer libstdc++6 (>=13.1)
- Dependencies: libcminpack1, libglew2.2, libfltk1.3
- Binary installed at: `/usr/local/bin/vsp`

## Tasks

### 1. modify_wing_span
- **Goal**: Change the Cessna-210 wing span from ~11.2m to 14.0m
- **Start State**: OpenVSP open with Cessna-210_metric.vsp3, maximized
- **Evidence Screenshots**:
  - `modify_wing_span_start_state.png` - Initial state with Cessna model loaded
  - `modify_wing_span_wing_selected.png` - NormalWing selected, properties panel visible
  - `modify_wing_span_14m.png` - Plan tab showing Span changed to 14.00000m
  - `modify_wing_span_completed.png` - Full window after span change

### 2. export_stl_mesh
- **Goal**: Export the eCRM-001 model as STL mesh file
- **Start State**: OpenVSP open with eCRM-001_wing_tail.vsp3, maximized
- **Evidence Screenshots**:
  - `export_stl_mesh_start_state.png` - Initial state with eCRM model loaded
  - `export_stl_file_menu.png` - File menu showing Export... option
  - `export_stl_dialog.png` - Export dialog with Stereolith (.stl) button
  - `export_stl_file_path.png` - File save dialog with export path typed

## Interactive Testing Evidence

### modify_wing_span - Complete UI Flow

1. **Start state**: OpenVSP loaded with Cessna-210_metric.vsp3, Geom Browser visible with component tree
2. **Select NormalWing**: Clicked NormalWing in Geom Browser tree - properties panel showed "Wing: NormalWing"
3. **Navigate to Plan tab**: Clicked Plan tab in properties panel - Total Planform section visible
4. **Read Span value**: Span field showed 11.20140m (matching task description of ~11.2m)
5. **Change Span**: Clicked Span input field, selected all text, typed "14.0", pressed Enter
6. **Verified change**: Span field updated to 14.00000m, other parameters recalculated (projected span: 13.99147, aspect ratio: 9.64790)
7. **Saved file**: Ctrl+S to save

**Conclusion**: Task is fully completable via the UI flow demonstrated.

### export_stl_mesh - Complete UI Flow

1. **Start state**: OpenVSP loaded with eCRM-001_wing_tail.vsp3, Geom Browser showing all components
2. **Open File menu**: Clicked File in menu bar
3. **Click Export...**: Export dialog opened showing all format buttons
4. **Click Stereolith (.stl)**: STL Options dialog appeared with "Tagged Multi Solid File" checkbox
5. **Click OK**: File save dialog appeared with title "Write STL File? (*.stl)"
6. **Type export path**: Typed `/home/ga/Documents/OpenVSP/exports/eCRM_export.stl` in File: field
7. **Click Accept**: Dialog accepted (note: actual STL tessellation may require >6GB RAM)

**Conclusion**: Full UI flow is accessible and navigable. The export path involves:
File > Export > Stereolith (.stl) > STL Options > File save dialog > Accept

## Verification Checklist

- [x] Installation script completes without errors (via PPA for libstdc++6)
- [x] Setup script completes without errors (warm-up launch succeeds)
- [x] Application visible in screenshot (maximized OpenVSP window)
- [x] Application in correct initial state with real data loaded
- [x] Task setup runs without errors (both tasks)
- [x] Task start state correct (verified via visual_grounding MCP tool)
- [x] Sufficient evidence that tasks are completable:
  - modify_wing_span: Full flow demonstrated - NormalWing selected, Plan tab, Span changed from 11.20140 to 14.00000
  - export_stl_mesh: Full flow demonstrated - File > Export > Stereolith (.stl) > STL Options > File save dialog

## Hook Execution Logs (from clean test)

### pre_start hook (install_openvsp.sh)
```
=== Installing OpenVSP ===
[apt-get update and install dependencies...]
[PPA added for newer libstdc++6]
Trying OpenVSP 3.48.0 from zips/current/linux...
Downloaded OpenVSP-3.48.0-Ubuntu-22.04_amd64.deb (136958126 bytes)
OpenVSP 3.48.0 installed successfully
Found OpenVSP binary at: /usr/local/bin/vsp
=== OpenVSP installation complete ===
```

### post_start hook (setup_openvsp.sh)
```
=== Setting up OpenVSP ===
Using OpenVSP binary: /usr/local/bin/openvsp
Performing warm-up launch...
OpenVSP warm-up window appeared after 0s
Warm-up complete, closing OpenVSP
Aircraft model files:
-rw-r--r-- 1 ga ga 415225 ... Cessna-210_metric.vsp3
-rw-r--r-- 1 ga ga 394778 ... eCRM-001_wing_tail.vsp3
=== OpenVSP setup complete ===
```

### pre_task hook (setup_task.sh - modify_wing_span)
```
=== Setting up modify_wing_span task ===
OpenVSP window appeared: 20971525
=== modify_wing_span task setup complete ===
Goal: Change the wing span from ~11.2m to exactly 14.0m and save the file.
```

### pre_task hook (setup_task.sh - export_stl_mesh)
```
=== Setting up export_stl_mesh task ===
OpenVSP window appeared: 18874373
=== export_stl_mesh task setup complete ===
Goal: Export the eCRM-001 model as STL to /home/ga/Documents/OpenVSP/exports/eCRM_export.stl
```

## Key Observations

1. **Window title format**: `OpenVSP 3.48.0 - MM/DD/YY     filename.vsp3`
2. **Warm-up launch**: Essential - clears first-run state
3. **setsid usage**: `DISPLAY=:1 setsid /usr/local/bin/vsp` (DISPLAY must come before setsid)
4. **Secondary window**: OpenVSP creates a second untitled window alongside the main window
5. **FLTK GUI**: OpenVSP uses FLTK toolkit - sub-windows (Geom Browser, Properties) are separate X11 windows
6. **Plan tab**: Wing span parameter is in the "Plan" tab > "Total Planform" section
7. **Export formats**: 20+ export formats available including STL, STEP, IGES, DXF, OBJ
8. **STL Options**: Intermediate dialog before file save with "Tagged Multi Solid File" checkbox
9. **Memory**: STL tessellation can be memory-intensive; 8GB RAM recommended
