# FreeCAD Environment (freecad_envb) — Evidence Documentation

## Environment Summary

- **Application**: FreeCAD 0.19.2 (installed via `apt-get install freecad` on Ubuntu 22.04 GNOME)
- **Platform**: QEMU VM, 1920×1080 display
- **Tasks**: 5 tasks covering primitive creation, 2D sketching, STL export, and boolean operations
- **Real data**: T8_housing_bracket.FCStd (FreeCAD parts library), contact_blocks.FCStd (FreeCAD FEM test suite)

---

## Checklist

- [x] FreeCAD installed and verified (`/usr/bin/freecad`)
- [x] Real data files mounted and copied (T8_housing_bracket.FCStd: 33868 bytes, contact_blocks.FCStd: 103262 bytes)
- [x] All 5 task pre_task hooks run successfully
- [x] FreeCAD window opens for all tasks
- [x] Model tree (Combo View) visible for all tasks
- [x] Part workbench active for primitive creation tasks
- [x] Real mechanical model loaded for export_to_stl task
- [x] Real FEM geometry loaded for fuse_shapes task
- [x] Screenshots taken independently for each task
- [x] Verifier stubs in place

---

## Installation Log (`install_freecad.sh` — pre_start hook)

```
=== Installing FreeCAD ===
...
FreeCAD version: FreeCAD 0.19
...
=== FreeCAD installation complete ===
```

Key packages installed: `freecad`, `xdotool`, `wmctrl`, `imagemagick`, `scrot`

---

## Post-Start Setup Log (`setup_freecad.sh` — post_start hook)

```
=== Setting up FreeCAD environment ===
Copying real FreeCAD data files...
T8_housing_bracket.FCStd: 33868 bytes
contact_blocks.FCStd: 103262 bytes
FreeCAD found at: /usr/bin/freecad
=== FreeCAD setup complete ===
```

Exit code: 0

**Data file provenance:**
- `T8_housing_bracket.FCStd` — Real T8 lead screw housing bracket from the official
  [FreeCAD-library](https://github.com/FreeCAD/FreeCAD-library) (Mechanical Parts/Mountings/).
  Contains: App::Part, PartDesign::Body, Sketcher workbench features, Pad, Hole (×2), Pocket, PolarPattern.
- `contact_blocks.FCStd` — Derived from FreeCAD's own FEM test suite
  (`Mod/Fem/femtest/data/calculix/constraint_contact_solid_solid.FCStd`).
  Modified to show only the two steel block solids (TopBox, BottomBox) with FEM analysis objects hidden.
  File size: 103262 bytes.

---

## Task 1: create_box — Pre-task Setup Log

```
=== Setting up create_box task ===
=== create_box task setup complete ===
FreeCAD is running. Agent should see FreeCAD with a new empty document.
Active windows:
0x02000003 -1 ga-base @!0,0;BDHF
0x0080010d  0 ga-base FreeCAD 0.19
```

**Start state**: FreeCAD 0.19 open, Part workbench active, Combo View showing empty "Unnamed" document.
**Evidence**: `create_box_start_state.png` — Python console shows `create_box task - test run 1`.

---

## Task 2: create_cylinder — Pre-task Setup Log

```
=== Setting up create_cylinder task ===
=== create_cylinder task setup complete ===
FreeCAD is running with a new empty document.
Active windows:
0x02000003 -1 ga-base @!0,0;BDHF
0x0080010d  0 ga-base FreeCAD 0.19
```

**Start state**: FreeCAD 0.19 open, Part workbench active, Combo View showing empty "Unnamed" document.
**Evidence**: `create_cylinder_start_state.png` — Python console shows `create_cylinder task - test run 2`.

---

## Task 3: create_sketch — Pre-task Setup Log

```
=== Setting up create_sketch task ===
=== create_sketch task setup complete ===
FreeCAD is running with a new empty document.
The agent should switch to the Sketcher workbench and create a new sketch.
Active windows:
0x02000003 -1 ga-base @!0,0;BDHF
0x0080010d  0 ga-base FreeCAD 0.19
```

**Start state**: FreeCAD 0.19 open, Part workbench active, Combo View showing empty "Unnamed" document.
**Evidence**: `create_sketch_start_state.png` — Python console shows `create_sketch task - test run 3`.

---

## Task 4: export_to_stl — Pre-task Setup Log

```
=== Setting up export_to_stl task ===
T8 bracket model size: 33868 bytes
=== export_to_stl task setup complete ===
FreeCAD is running with T8_housing_bracket.FCStd loaded.
Active windows:
0x02000003 -1 ga-base @!0,0;BDHF
0x0080010d  0 ga-base FreeCAD 0.19
```

**Start state**: FreeCAD showing T8 housing bracket model. Model tree shows: Bracket → Body → Origin001, Pad, Hole, Pocket, Hole001, PolarPattern. 3D viewport shows a flat mounting plate with 4 holes in polar pattern.
**Evidence**: `export_to_stl_start_state.png` — Full 1920×1080, model tree items legible.

---

## Task 5: fuse_shapes — Pre-task Setup Log

```
=== Setting up fuse_shapes task ===
Contact blocks model size: 103262 bytes
=== fuse_shapes task setup complete ===
FreeCAD is running with contact_blocks.FCStd loaded.
Active windows:
0x02000003 -1 ga-base @!0,0;BDHF
0x0080010d  0 ga-base FreeCAD 0.19
```

**Start state**: FreeCAD showing contact_blocks.FCStd. Model tree shows TopBox and BottomBox as separate selectable Part::Box solids. 3D viewport shows two rectangular blocks in contact.
**Evidence**: `fuse_shapes_start_state.png` — Full 1920×1080, TopBox and BottomBox names legible in tree.

---

## Screenshots

| File | Description |
|------|-------------|
| `create_box_start_state.png` | FreeCAD open, Part workbench, empty doc. Console: `create_box task - test run 1` |
| `create_cylinder_start_state.png` | FreeCAD open, Part workbench, empty doc. Console: `create_cylinder task - test run 2` |
| `create_sketch_start_state.png` | FreeCAD open, Part workbench, empty doc. Console: `create_sketch task - test run 3` |
| `export_to_stl_start_state.png` | T8 housing bracket loaded. PartDesign tree visible. |
| `fuse_shapes_start_state.png` | contact_blocks.FCStd loaded. TopBox + BottomBox in tree. |

All screenshots are 1920×1080, taken independently from separate setup_task.sh runs.

---

## Key Implementation Notes

1. **FCStd files must be created in GUI mode** — FreeCAD headless (no DISPLAY) omits `GuiDocument.xml`, resulting in an empty viewport. All pre-placed `.FCStd` files were created or processed in GUI mode to include proper camera/visibility data.

2. **Combo View not persistent** — FreeCAD 0.19 does not persist the Combo View panel after process kill. Each `setup_task.sh` re-opens it via `View > Panels > Combo View` using xdotool at verified pixel coordinates (View: 153,72 → Panels: 177,603 → Combo View: 561,655).

3. **XAUTHORITY required** — All `xdotool`/`wmctrl` commands run as root must include `XAUTHORITY=/home/ga/.Xauthority` to access the ga user's X11 display session.

4. **Real data**: No synthetic or mock FCStd files. Both data-driven tasks use real-world engineering geometry:
   - `T8_housing_bracket.FCStd`: A real T8 lead screw mounting bracket from the official FreeCAD community parts library
   - `contact_blocks.FCStd`: Real FEM contact mechanics test geometry from FreeCAD's own shipped test suite, with FEM analysis objects hidden to expose the two structural blocks
