# LibreCAD Environment — Evidence Documentation

## Environment Overview

- **Environment ID**: `librecad_env@0.1`
- **Base image**: `ubuntu-gnome-systemd_highres` (1920×1080 GNOME desktop)
- **LibreCAD version**: 2.1.3-3 (installed via `apt-get install librecad`)
- **Real data file**: `floorplan.dxf` — genuine 2-car garage architectural construction drawing
  - Source: `https://raw.githubusercontent.com/jscad/sample-files/master/dxf/dxf-parser/floorplan.dxf`
  - File size: 1,117,143 bytes (~1.1 MB)
  - Layers: 24 named layers (A-DIMS-1, A-NOTE, A-TEXT, xref-Bishop-Overland-*, etc.)
  - Entities: 967 total (TEXT, LINE, ARC, INSERT, etc.)
- **Python DXF library**: `ezdxf` (for verification)

---

## Task Start-State Screenshots

### 1. draw_rectangle — Blank canvas, LibreCAD with new drawing

**Screenshot**: `draw_rectangle_start_state.png`

LibreCAD opens with a blank new drawing on layer `0`. The task requires drawing a 3000×2000 unit rectangle with bottom-left at (0,0). The Rectangle tool is found under Tools > Line > Rectangle. After clicking two canvas corners, the system prompts "Specify first corner" then "Specify second corner".

**Confirmed via visual_grounding**:
- LibreCAD blank canvas visible
- Layer panel shows default layer `0`
- Menu bar: File, Options, Edit, View, Plugins, Tools, Widgets, Drawings, Help

---

### 2. add_layer — Real floorplan.dxf loaded

**Screenshot**: `add_layer_floorplan_loaded.png`

LibreCAD opens with the real architectural floor plan at `/home/ga/Documents/LibreCAD/floorplan.dxf`. Task requires adding "Dimensions" (red) and "Notes" (blue) layers.

**Confirmed via visual_grounding**:
- Real 2-car garage floor plan visible
- Text annotations: "2 CAR GARAGE 21'2 x 20'10", wall bracing specs, "16070 O.H. DOOR"
- Layer panel shows: 0, A-DIMS-1, A-NOTE, A-TEXT, ANNTEXT, Defpoints, TEMP, View Port, xref-*

---

### 3. add_dimensions — Real floorplan.dxf, ready for dimension annotation

**Screenshot**: `add_dimensions_start_state.png`

LibreCAD opens with the real floor plan. Task requires adding a new layer named "Dimensions" and placing a horizontal linear dimension across the full width of the drawing's outermost bounding box.

**Confirmed via visual_grounding**:
- Real floor plan with construction annotations visible
- Cyan text with wall bracing notes, dimensional markers (31.80, 105.60, 31.80)
- Layer panel shows A-DIMS, A-NOTE, A-TEXT layers

---

### 4. export_to_pdf — Real floorplan.dxf, ready for PDF export

**Screenshot**: `export_to_pdf_start_state.png`

LibreCAD opens with the real floor plan at `/home/ga/Documents/LibreCAD/floorplan.dxf`. Task requires exporting to `/home/ga/Documents/LibreCAD/floorplan_export.pdf`.

**Confirmed via visual_grounding**:
- Real 2-car garage floor plan visible with construction details
- Red wall panels, blue dimension lines, cyan annotation text
- Menu bar accessible (File menu contains Print/Export options)

---

### 5. modify_text — Real floorplan.dxf, ready for text annotation

**Screenshot**: `modify_text_start_state.png`

LibreCAD opens with the real floor plan. Task requires adding "APPROVED FOR CONSTRUCTION" text on layer `A-TEXT`. The existing `A-TEXT` layer is visible in the layer panel.

**Confirmed via visual_grounding**:
- Real floor plan with existing text (construction notes) visible
- Layer panel clearly shows `A-TEXT` layer listed
- Title bar: "LibreCAD - [/home/ga/Documents/LibreCAD/floorplan.dxf]"

---

## Log Snippets

### LibreCAD warm-up launch log (`/tmp/librecad_warmup.log`)
```
RS_DEBUG::setLevel(3)
RS_DEBUG: Critical
RS_DEBUG: Errors
RS_DEBUG: Warnings
QStandardPaths: XDG_RUNTIME_DIR not set, defaulting to '/tmp/runtime-ga'
```

### LibreCAD task launch log (`/tmp/librecad_task.log`)
```
RS_DEBUG::setLevel(3)
RS_DEBUG: Critical
RS_DEBUG: Errors
RS_DEBUG: Warnings
RS_FilterDXF::addLayer: layer View Port have extended data
```
(The "View Port" extended data message is expected — the real DXF uses extended data on this layer, LibreCAD loads it fine.)

### DXF verification (Python ezdxf)
```
python3 -c "import ezdxf; d=ezdxf.readfile('/home/ga/Documents/LibreCAD/floorplan.dxf'); print('Layers:', len(list(d.layers))); print('Entities:', len(list(d.modelspace())))"
Layers: 24
Entities: 967
```

### floorplan.dxf validation
```
stat -c '%s' /home/ga/Documents/LibreCAD/floorplan.dxf
1117143
```

---

## Interactive Testing Notes

- **Screenshot method**: `import -window root /tmp/screen.png` (captures GNOME composited desktop correctly; VNC and `scrot` return black screens due to compositor)
- **Coordinate scaling**: visual_grounding returns 1280×720 coords; actual 1920×1080; scale factor 1.5x
- **SSH user**: `ga` (password: `password123`)
- **DISPLAY**: `:1`
- **LibreCAD process**: `pgrep -la librecad` → confirms running
- **su vs direct launch**: SSH as `ga` directly — do NOT use `su - ga` inside scripts when already SSHed as `ga`

---

## Files in This Directory

| File | Description |
|------|-------------|
| `draw_rectangle_start_state.png` | Blank LibreCAD canvas (new drawing) |
| `add_layer_floorplan_loaded.png` | Real floorplan.dxf loaded in LibreCAD |
| `add_dimensions_start_state.png` | Real floorplan.dxf, ready for dimension annotation |
| `export_to_pdf_start_state.png` | Real floorplan.dxf, ready for PDF export |
| `modify_text_start_state.png` | Real floorplan.dxf with A-TEXT layer visible |
| `README.md` | This file |
