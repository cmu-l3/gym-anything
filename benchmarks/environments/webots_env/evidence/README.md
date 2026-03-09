# Webots Environment — Evidence Documentation

## Overview

This directory contains screenshots and documentation verifying that the Webots robot simulator environment (`webots_env@0.1`) was successfully installed, configured, and tested inside a QEMU/Apptainer VM.

## Environment Summary

| Property | Value |
|----------|-------|
| Environment ID | `webots_env@0.1` |
| Application | Webots R2023b (Cyberbotics 3D robot simulator) |
| Base Image | `ubuntu-gnome-systemd_highres` |
| Resolution | 1920x1080 |
| Resources | 4 CPU, 8 GB RAM, no GPU |
| Rendering | Mesa software rendering (`LIBGL_ALWAYS_SOFTWARE=1`) |
| Install Path | `/usr/local/webots/` |

## Evidence Screenshots

### 01_desktop_with_webots_shortcut.png
**Verifies**: VM boots to desktop, Webots shortcut is visible.
- GNOME desktop fully rendered at 1920x1080
- Webots desktop shortcut created by `setup_webots.sh`
- Desktop environment functional and ready for GUI interaction

### 02_webots_soccer_world_loaded.png
**Verifies**: Webots launches and loads demo world files correctly.
- Webots R2023b main window open with `soccer.wbt` loaded
- 3D viewport shows soccer field with robots
- Scene tree panel visible on left side
- Console panel visible at bottom
- Window title reflects the loaded world file

### 03_worldinfo_expanded_properties.png
**Verifies**: Scene tree nodes are expandable and WorldInfo properties are accessible.
- WorldInfo node expanded in scene tree
- Properties panel below shows WorldInfo fields
- `gravity` field visible with value `9.81`
- `basicTimeStep` field visible with value `32`

### 04_basictimestep_editable_field.png
**Verifies**: The `basicTimeStep` field is visible and editable (used by `change_timestep` task).
- `basicTimeStep` field shown with current value `32`
- Field is editable via the properties panel
- Confirms the task to change this value from 32 to 64 is feasible

### 05_gravity_editable_field.png
**Verifies**: The `gravity` field is visible and editable (used by `modify_gravity` task).
- `gravity` field shown with current value `9.81`
- Field is editable via the properties panel
- Confirms the task to change this value from 9.81 to 3.72 is feasible

## Setup Log Snippets

### install_webots.sh (pre_start hook)
```
=== Installing Webots Robot Simulator ===
Installing OpenGL and Mesa dependencies...
Installing GUI automation tools...
Downloading Webots R2023b...
Installing Webots .deb package...
Webots installed successfully at /usr/local/webots/
=== Webots installation complete ===
```

### setup_webots.sh (post_start hook)
```
=== Setting up Webots configuration ===
Configuring Webots preferences...
=== Webots setup complete ===
```

### Manual verification via SSH
```bash
$ ls /usr/local/webots/webots
/usr/local/webots/webots    # Binary exists and is executable

$ ls /usr/local/webots/projects/samples/demos/worlds/
soccer.wbt
highway_overtaking.wbt
moon.wbt
# ... (6 demo worlds total)

$ DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 /usr/local/webots/webots --batch --mode=pause \
    /usr/local/webots/projects/samples/demos/worlds/soccer.wbt &
# Webots launched successfully, window appeared within 30s
```

## Checklist Verification

| # | Check | Status |
|---|-------|--------|
| 1 | VM boots and SSH is accessible | PASS |
| 2 | pre_start hook installs Webots successfully | PASS |
| 3 | post_start hook configures preferences and env vars | PASS |
| 4 | Webots binary exists at `/usr/local/webots/webots` | PASS |
| 5 | Demo world files present in `projects/samples/demos/worlds/` | PASS |
| 6 | Webots launches with `--batch --mode=pause` | PASS |
| 7 | Soccer demo world loads with 3D viewport | PASS |
| 8 | Scene tree shows WorldInfo with gravity and basicTimeStep | PASS |
| 9 | Properties are editable via field editor panel | PASS |
| 10 | Dialog suppression works (Qt config + `--batch`) | PASS |
| 11 | Desktop shortcut created | PASS |
| 12 | Software rendering works without GPU | PASS |

## Tasks

| Task | Difficulty | Description |
|------|-----------|-------------|
| `open_and_run_simulation` | Easy | Open soccer demo world and start simulation |
| `save_world_as` | Easy | Save loaded world to a new file path |
| `change_timestep` | Easy | Change WorldInfo.basicTimeStep from 32 to 64 |
| `modify_gravity` | Medium | Change WorldInfo.gravity from 9.81 to 3.72 |

## Task End-to-End Verification (via visual_grounding)

### change_timestep task

Verified via `from_config("benchmarks/environments/webots_env", task_id="change_timestep")` with `env.reset(seed=42, use_cache=True, cache_level="pre_start")`.

| Screenshot | Description |
|-----------|-------------|
| `06_change_timestep_task_start.png` | Task start state: Webots open with soccer.wbt, scene tree visible, simulation paused at 0:00:00 |
| `07_worldinfo_expanded_fields.png` | WorldInfo expanded: shows gravity=9.81, basicTimeStep=32, title="Soccer Game" |
| `08_basictimestep_editable_spinbox.png` | basicTimeStep selected: properties panel shows editable spinbox with value 32 |
| `09_basictimestep_changed_to_64.png` | basicTimeStep changed: both scene tree and spinbox now show 64 |
| `10_save_world_as_dialog.png` | File > Save World As... dialog open, filename field visible with Save button |
| `11_file_saved_with_new_title.png` | File saved: window title shows `/home/ga/Desktop/modified_soccer.wbt`, basicTimeStep=64 in scene tree |

**File verification**: `grep "basicTimeStep" /home/ga/Desktop/modified_soccer.wbt` → `basicTimeStep 64`

### modify_gravity task

Verified via `from_config("benchmarks/environments/webots_env", task_id="modify_gravity")` with `env.reset(seed=42, use_cache=True, cache_level="pre_start")`.

| Screenshot | Description |
|-----------|-------------|
| `12_modify_gravity_task_start.png` | Task start state: Webots open with gravity_world.wbt (soccer demo), simulation paused |
| `13_gravity_field_9_81.png` | WorldInfo expanded: gravity=9.81 (Earth default), basicTimeStep=32 |
| `14_gravity_editable_spinbox.png` | gravity selected: properties panel shows "Selection: gravity (Float)" with spinbox value 9.81 |
| `15_gravity_changed_to_3_72.png` | gravity changed: both scene tree and spinbox now show 3.72 (Mars gravity) |

### save_world_as task

Verified via `from_config("benchmarks/environments/webots_env", task_id="save_world_as")` with `env.reset(seed=42, use_cache=True, cache_level="pre_start")`.

| Screenshot | Description |
|-----------|-------------|
| `16_save_world_as_task_start.png` | Task start state: Webots open with `highway_overtake.wbt` — multi-lane highway scene with Lincoln MKZ vehicle, guardrails, traffic. Simulation paused. |
| `17_save_world_as_file_menu.png` | File menu open: "Save World As..." option visible (6th item) |
| `18_save_world_as_dialog.png` | Save World File dialog open: current dir `/home/ga`, filename field shows `highway_overtake.wbt`, Save/Cancel buttons visible |

### open_and_run_simulation task

Verified via `from_config("benchmarks/environments/webots_env", task_id="open_and_run_simulation")` with `env.reset(seed=42, use_cache=True, cache_level="pre_start")`.

| Screenshot | Description |
|-----------|-------------|
| `19_open_run_sim_task_start_empty.png` | Task start state: Webots open with `empty.wbt` — blank 3D viewport, scene tree shows only WorldInfo and Viewpoint |
| `20_open_run_sim_file_menu.png` | File menu open: "Open Sample World..." option visible (4th item) |
| `21_open_sample_world_dialog.png` | Open Sample World dialog: 5 top-level categories (humans, languages, robots, samples, vehicles) |
| `22_samples_category_expanded.png` | "samples" category expanded: subcategories including contests, curriculum, **demos**, devices, etc. |
| `23_demos_with_soccer_wbt.png` | "demos" subcategory expanded: 6 worlds visible including **soccer.wbt** |
| `24_soccer_world_loaded.png` | Soccer world loaded: 3D viewport shows soccer field with colored robot teams, title bar confirms `soccer.wbt (demos)` |
| `25_simulation_running.png` | Simulation running: timer at 0:00:00:032, console shows "Starting controller" messages for soccer_player and soccer_referee_supervisor |

## Known Issues

1. **Memory usage**: Webots with Mesa software rendering needs ~8 GB RAM minimum. Earlier tests with 6 GB caused OOM kills during installation.
2. **SSH timing after checkpoint restore**: Framework's exec() SSH key auth fails (code 255) on first attempt after checkpoint restore; paramiko fallback works.
3. **No warm-up launch**: Warm-up Webots launches were removed from `setup_webots.sh` to save memory — dialog suppression is handled entirely by Qt config file and `--batch` flag.
