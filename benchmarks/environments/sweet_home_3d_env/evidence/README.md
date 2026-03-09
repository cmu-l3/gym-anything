# Sweet Home 3D Environment - Evidence Documentation

## Environment Overview

- **Application**: Sweet Home 3D 7.5 (Java-based interior design application)
- **Base Image**: ubuntu-gnome-systemd_highres (1920x1080)
- **Resources**: 4 CPU, 6GB RAM, net enabled
- **Installation Method**: Official Linux 64-bit tarball from SourceForge (bundles its own JRE)
- **Real Data**: Official .sh3d sample files from the Sweet Home 3D gallery

## Data Sources (Real Data)

All data files are **real, official sample home plans** from the Sweet Home 3D gallery (https://www.sweethome3d.com/gallery/):

| File | Size | Source URL | Description |
|------|------|-----------|-------------|
| userGuideExample.sh3d | 2,258,779 bytes | https://www.sweethome3d.com/benchmarks/environments/userGuideExample.sh3d | Basic furnished apartment |
| SweetHome3DExample.sh3d | 1,764,708 bytes | https://www.sweethome3d.com/benchmarks/environments/SweetHome3DExample.sh3d | Basic apartment |
| SweetHome3DExample7.sh3d | 6,956,367 bytes | https://www.sweethome3d.com/benchmarks/environments/SweetHome3DExample7.sh3d | Contemporary villa with multiple rooms |

These are complete home plans with walls, rooms, furniture, textures, and 3D models — not synthetic or mock data.

---

## Task 1: add_furniture_to_room — Interactive Testing Evidence

### Start State
- **Plan**: userGuideExample.sh3d (basic apartment from official gallery)
- **Goal**: Add a round table from the furniture catalog to the floor plan
- **Window title**: "userGuideExample.sh3d - Sweet Home 3D"

### Step-by-step Evidence (screenshot → visual_grounding → action → screenshot)

**Step 0 - Verify start state** (`task1_step0_start_state.png`):
- Application visible and maximized
- Real floor plan loaded with rooms, walls, and furniture visible
- Furniture catalog on left showing categories: Bathroom, Bedroom, Doors and windows, Kitchen, Lights, Living room, Miscellaneous, Staircases
- 2D floor plan showing "My home" with "Living room 232 sq ft" labeled
- 3D perspective view in bottom-right showing rendered interior

**Step 2 - Expand Living room category** (`task1_step2_living_room_expanded.png`):
- Clicked on "Living room" category in furniture catalog
- Category expanded showing items: Aquarium, Armchair, Bookcase, Chair, Coffee table, Corner sofa, Desk, Dresser, Filled bookcase, Fireplace, Flat TV, Flowers

**Step 3 - Scroll to find tables** (`task1_step3_tables_visible.png`):
- Scrolled down in furniture catalog
- Found 3 table items: **Round table**, **Square table**, **Table**
- Also visible: Piano, Plant, Sofa, Stool, TV unit

**Step 6 - Open Furniture menu** (`task1_step6_furniture_menu.png`):
- Selected "Round table" in catalog (highlighted in blue)
- Opened Furniture menu from menu bar
- Menu shows "Add to home" (Ctrl+Alt+F) as first option
- Also shows: Add to group, Modify..., Group, Import furniture..., etc.

**Step 7 - Table added to plan** (`task1_step7_table_added.png`):
- Clicked "Add to home" to add the Round table
- **Result: Round table successfully added to the floor plan**
- Furniture list at bottom now shows **2 "Round table" entries** (one pre-existing, one newly added)
- Confirms task is completable end-to-end

### Setup Logs (Task 1):
```
=== Setting up add_furniture_to_room task ===
Using plan file: /home/ga/Documents/SweetHome3D/userGuideExample.sh3d (2258779 bytes)
Killing any existing Sweet Home 3D instances...
Launching Sweet Home 3D...
Sweet Home 3D window detected after 2s (WID: 8388615)
Waiting for application to fully load...
Dismissing startup dialogs...
Maximizing window...
Window maximized and focused (WID: 8388798)
Taking initial screenshot...
Sweet Home 3D task setup complete
=== add_furniture_to_room task setup complete ===
```

---

## Task 2: create_photo_rendering — Interactive Testing Evidence

### Start State
- **Plan**: SweetHome3DExample7.sh3d (contemporary villa from official gallery)
- **Goal**: Create a photorealistic rendering via 3D View > Create photo...
- **Window title**: "SweetHome3DExample7.sh3d - Sweet Home 3D"

### Step-by-step Evidence (screenshot → visual_grounding → action → screenshot)

**Step 0 - Verify start state** (`task2_step0_start_state.png`):
- Application visible and maximized
- Contemporary villa plan loaded with multiple rooms:
  - Living room (346 sq ft), Kitchen (134 sq ft), Garage (400 sq ft), Bedroom, Bathroom, Entrance
- Real furniture: armchairs, bar stools, beds, tables, sofas, cars in garage
- Trees and landscaping visible outside
- 3D view showing detailed interior with fireplace, couches, dining area

**Step 1 - Click 3D view menu** (`task2_step1_3dview_menu.png`):
- Clicked "3D view" in menu bar
- Dropdown shows options including:
  - Aerial view, Virtual visit, Modify virtual visitor...
  - Display in separate window, Modify 3D view...
  - **Create photo...** (target option)
  - Create photos at points of view...
  - Create video...
  - Export to OBJ format...

**Step 2 - Create photo dialog opens** (`task2_step2_create_photo_dialog.png`):
- Clicked "Create photo..."
- Dialog opened with settings:
  - Width: 1,200 pixels, Height: 900 pixels
  - Apply proportions: 4:3
  - Quality slider: Fast to Best
  - Date: 3/28/2013, Time: 12:00 PM
  - Lens: Default, Add ceiling lights checkbox
  - Renderer: Sunflow
  - Buttons: Create, Save..., Close

**Step 4 - Rendering complete** (`task2_step4_rendering_complete.png`):
- Clicked "Create" button and waited for rendering
- **Rendered image now visible** showing:
  - Brown/tan upholstered sofa with decorative cushions
  - Wooden dining table with black modern chairs
  - White plates and turquoise vase on table
  - Golden-yellow door with vertical panels
  - Green potted plant, natural lighting
- Save button active and ready
- Stop/Save/Close buttons available

**Step 8 - Final rendering state** (`task2_step8_rendering_final.png`):
- Full rendering visible with detailed interior scene
- Save... button available for saving the rendered photo to disk
- Confirms task is completable end-to-end

### Setup Logs (Task 2):
```
=== Setting up create_photo_rendering task ===
Using plan file: /home/ga/Documents/SweetHome3D/SweetHome3DExample7.sh3d (6956367 bytes)
Killing any existing Sweet Home 3D instances...
Launching Sweet Home 3D...
Sweet Home 3D window detected after 2s (WID: 8388615)
Waiting for application to fully load...
Dismissing startup dialogs...
Maximizing window...
Window maximized and focused (WID: 8388847)
Taking initial screenshot...
Sweet Home 3D task setup complete
=== create_photo_rendering task setup complete ===
```

---

## Installation Evidence

### Pre-start log (install_sweet_home_3d.sh):
```
=== Installing Sweet Home 3D ===
[apt-get update and install output...]
Downloading Sweet Home 3D 7.5...
Download successful on attempt 1
Extracting Sweet Home 3D...
Sweet Home 3D installed at /opt/SweetHome3D/
Downloading real sample home plans from official Sweet Home 3D gallery...
Downloading userGuideExample.sh3d...
Downloading SweetHome3DExample.sh3d...
Downloading SweetHome3DExample7.sh3d...
  SweetHome3DExample7.sh3d: 6956367 bytes
  SweetHome3DExample.sh3d: 1764708 bytes
  userGuideExample.sh3d: 2258779 bytes
Downloaded 3 sample home plans
=== Sweet Home 3D installation complete ===
```

### Post-start log (setup_sweet_home_3d.sh):
```
=== Setting up Sweet Home 3D ===
Desktop is ready
Copying sample home plans to user directory...
Performing warm-up launch...
Waiting for Sweet Home 3D window...
Sweet Home 3D window detected (WID: 8388738)
Dismissing any startup dialogs...
Killing warm-up instance...
Verifying setup...
  Sweet Home 3D binary: OK
  Sample plans available: 3
=== Sweet Home 3D setup complete ===
```

---

## Verification Checklist

- [x] Installation script completes without errors (pre_start: ~69s)
- [x] Setup script completes without errors (post_start)
- [x] 3 real sample .sh3d files downloaded from official gallery
- [x] Sweet Home 3D warm-up launch succeeds, window detected
- [x] Task 1 setup runs without errors (pre_task: ~23s)
- [x] Task 1 start state correct: userGuideExample.sh3d loaded, furniture catalog visible, plan visible
- [x] Task 1 completable: Round table added from Living room category via Furniture > Add to home
- [x] Task 2 setup runs without errors (pre_task: ~23s)
- [x] Task 2 start state correct: SweetHome3DExample7.sh3d loaded, villa plan and 3D view visible
- [x] Task 2 completable: 3D View > Create photo... opens dialog, rendering produces image, Save available
- [x] Real data visible in both tasks (floor plans, furniture, 3D views)
- [x] UI interactions work (xdotool click, scroll, keyboard)
- [x] All evidence confirmed via visual_grounding MCP tool

## Timing Summary

| Phase | Duration |
|-------|----------|
| Pre-start (install) | ~69s |
| Post-start (setup) | ~3s |
| Pre-task (task setup) | ~23s |
| **Total reset time** | **~92-99s** |
