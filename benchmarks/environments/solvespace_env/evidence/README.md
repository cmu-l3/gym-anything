# SolveSpace Environment — Evidence Documentation

This directory contains screenshots and logs from interactive testing of the `solvespace_env` environment.

## Environment Summary

| Item | Value |
|------|-------|
| Application | SolveSpace 3.0.rc2 |
| Install method | `apt-get install solvespace` (Ubuntu 22.04 repos) |
| Base image | `ubuntu-gnome-systemd_highres` (1920×1080) |
| Real data | Official SolveSpace tutorial files from `https://solvespace.com/dl/box-parts.zip` |
| Sample files | `base.slvs` (259085 bytes), `divider.slvs` (80251 bytes), `side.slvs` (252461 bytes) |

## Checklist

### Installation
- [x] `solvespace` package installs via `apt-get install solvespace`
- [x] `solvespace-cli` bundled with the package (available at `/usr/bin/solvespace-cli`)
- [x] Real data files downloaded from official SolveSpace tutorial: `box-parts.zip`
- [x] All 3 sample files validated: `base.slvs`, `divider.slvs`, `side.slvs` (all >100 bytes)
- [x] Correct permissions set on `/opt/solvespace_samples/`

### Post-start setup
- [x] Config directory created: `~/.config/solvespace/`
- [x] `settings.json` created with `"checkForUpdates": false`
- [x] Workspace created: `/home/ga/Documents/SolveSpace/`
- [x] Warm-up launch executed: SolveSpace window found via `wmctrl -l`
- [x] SolveSpace killed cleanly after warm-up

### Task Start States
- [x] `draw_rectangle`: Blank canvas — SolveSpace open with untitled new file
- [x] `draw_circle`: Blank canvas — SolveSpace open with untitled new file
- [x] `export_to_dxf`: `divider.slvs` loaded — real 2D panel from SolveSpace tutorial
- [x] `add_constraint`: `line_to_constrain.slvs` loaded — clean diagonal line, no H constraint (type=80)
- [x] `extrude_sketch`: Blank canvas — SolveSpace open with untitled new file

### End-to-End Task Completion (Interactive Testing)
- [x] `draw_rectangle`: Drew rectangle with R tool, saved as `rectangle.slvs` (screenshot 10)
- [x] `draw_circle`: Drew circle with C tool, saved as `circle.slvs` (screenshot 11)
- [x] `export_to_dxf`: Exported divider.slvs as `divider.dxf` via File > Export 2d View... (screenshot 09)
- [x] `add_constraint`: Added H constraint (Constrain > Horizontal) to diagonal line, saved as `side_constrained.slvs` (screenshot 12)
- [x] `extrude_sketch`: Drew rectangle + created extrude group (New Group > Extrude), saved as `block.slvs` (screenshot 13)

### Timing (from clean restart test)
- pre_start (install): 54s — `apt-get install solvespace` + download box-parts.zip (PASS)
- post_start (setup): 12s — config, warm-up launch
- pre_task (draw_rectangle): 13s
- Total env setup: 80s (from `use_cache=False, use_savevm=True` test)
- Note: First run without cache was ~646s due to the box-asm.zip bug (now fixed)

## Screenshots

### `00_solvespace_running.png`
SolveSpace 3.0.rc2 running with a new sketch in the canvas. Shows the application is correctly installed and launches.

### `01_draw_rectangle_start_state.png`
Start state for the `draw_rectangle` task: blank canvas, SolveSpace open maximized at 1920×1080.
The "Groups" list in the property browser shows the default sketch workplane (`g001` — XY plane).

### `02_export_to_dxf_start_state.png`
Start state for the `export_to_dxf` task: `divider.slvs` loaded and displayed.
This is a real parametric drawing of a wooden box divider from the official SolveSpace tutorial.
The drawing shows a rectangular profile with corner notches for box assembly.

### `03_add_constraint_start_state.png`
Start state for the `add_constraint` task: `line_to_constrain.slvs` loaded — a clean diagonal line with no constraints.
(Note: screenshot taken during early testing with `side.slvs`; task was updated to use `line_to_constrain.slvs` for a simpler, unambiguous start state with exactly one entity and zero constraints.)

### `04_sketch_menu_items.png`
SolveSpace Sketch menu open, showing available drawing tools:
- Line Segment (L)
- Tangent Arc at Point
- Circle (C)
- Arc of Circle (A)
- Bezier Cubic Spline
- Text in TrueType Font (T)
- Rectangle (R)
- etc.

### `05_constrain_menu_items.png`
SolveSpace Constrain menu open, showing available constraints:
- Distance / Diameter (D)
- Angle (N)
- Horizontal (H)
- Vertical (V)
- On Midpoint (M)
- Symmetric (Y)
- Equal (Q)
- Parallel / Tangent (L)
- Perpendicular (I)
- etc.

### `06_rectangle_drawing_demo.png`
Rectangle drawing in progress — shows the Sketch>Rectangle (R) tool being used to draw a rectangle on the canvas.

### `07_draw_circle_start_state.png`
Start state for the `draw_circle` task: blank canvas, SolveSpace open with g002-sketch-in-plane active.
The property browser shows the two default groups: g001-#references and g002-sketch-in-plane.

### `08_extrude_sketch_start_state.png`
Start state for the `extrude_sketch` task: blank canvas, SolveSpace open with g002-sketch-in-plane active.
Identical to draw_rectangle/draw_circle start states — the task starts from a blank file.

### `09_export_to_dxf_success.png`
Successful completion of the `export_to_dxf` task: DXF export dialog shown after File > Export 2d Section...
The export dialog shows format options (DXF/SVG/PDF/HPGL/Step) and the output path `divider.dxf`.
The resulting file (`/home/ga/Documents/SolveSpace/divider.dxf`) is a valid DXF verified by the task verifier.

### `10_draw_rectangle_success.png`
Successful completion of the `draw_rectangle` task: `rectangle.slvs` saved and displayed in canvas.
Title bar shows "rectangle.slvs — SolveSpace". The canvas shows a closed 4-sided polygon (rectangle)
drawn with the Sketch > Rectangle (R) tool and saved to `/home/ga/Documents/SolveSpace/rectangle.slvs`.

### `11_draw_circle_success.png`
Successful completion of the `draw_circle` task: `circle.slvs` saved and displayed in canvas.
Title bar shows "circle.slvs — SolveSpace". The canvas shows a circle drawn with the Sketch > Circle (C) tool,
saved to `/home/ga/Documents/SolveSpace/circle.slvs`. Verifier confirmed a Circle entity in the file.

### `12_add_constraint_success.png`
Successful completion of the `add_constraint` task: `side_constrained.slvs` saved with Horizontal constraint applied.
Title bar shows "side_constrained.slvs — SolveSpace". A pink/magenta **H** marker is visible on the diagonal line,
indicating `Constraint.type=80` (HORIZONTAL) was added via Constrain > Horizontal menu.
Verifier confirmed the constraint is present and the file saved successfully.

### `13_extrude_sketch_success.png`
Successful completion of the `extrude_sketch` task: `block.slvs` saved showing a 3D solid extrusion.
Title bar shows "block.slvs — SolveSpace". The 3D viewport (after middle-click orbit) shows a gray solid block
with green edges, created by: (1) drawing a rectangle in g002-sketch-in-plane, then (2) adding a new extrude group
via Group > New Group > Extrude. The file contains `Group.type=5100` (extrude) confirmed by verifier.

## Key Findings During Testing

### Critical Bug Found and Fixed
- **Bug**: `install_solvespace.sh` originally downloaded both `box-parts.zip` AND `box-asm.zip`
- **Root cause**: `box-asm.zip` contains `side.slvs` which also exists in `box-parts.zip`. Without `-o` flag, `unzip -q` prompts interactively for overwrite, hanging the SSH command.
- **Effect**: SSH command timed out (`[QemuApptainer] SSH command timed out: sudo -E bash -lc /workspace/scripts/install_solves...`)
- **Fix**: Removed the `box-asm.zip` download section entirely. Only `box-parts.zip` is needed for all tasks.

### SolveSpace Constraint and Group Types (in .slvs file format)
- `Constraint.type=20` = POINTS_COINCIDENT (not Horizontal!)
- `Constraint.type=80` = HORIZONTAL
- `Constraint.type=82` = VERTICAL
- `Group.type=5000` = sketch-in-plane (default sketch group)
- `Group.type=5100` = extrude (3D extrusion group)
- The `add_constraint` task: starts with 0 constraints, agent adds type=80

### SolveSpace Menu Structure (3.0.rc2)
- File > Export 2d Section... (**Ctrl+Shift+2**) — exports DXF/SVG/PDF
- Sketch menu: Rectangle (**R**), Circle (**C**), Line Segment (**L**), Arc (**A**)
- Constrain menu: Horizontal (**H**), Vertical (**V**), Distance/Diameter (**D**), Perpendicular (**I**)
- Group menu > New Group > **Extrude** — creates 3D extrusion from sketch
- Save As: **Ctrl+Shift+S**

### Screenshot Method
- `import -window root /path/to/out.png` works correctly (ImageMagick)
- `scrot` returns black screenshot with GNOME compositor — do NOT use
- VNC connection also available via `VNCConnection("localhost", 5900, password="password")`

### SolveSpace Process
- Binary: `/usr/bin/solvespace`
- CLI tool: `/usr/bin/solvespace-cli`
- Kill: `pkill -f /usr/bin/solvespace`
- Window detection: `wmctrl -l | grep -i solvespace`
- Launch as ga user: `su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority solvespace [file]"`
