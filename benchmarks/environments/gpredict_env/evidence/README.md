# GPredict Environment - Evidence Documentation

## Environment Overview

- **Application**: GPredict v2.2 (satellite tracking and orbit prediction)
- **Base image**: `ubuntu-gnome-systemd_highres` (1920x1080)
- **Installation**: `apt-get install gpredict` (Ubuntu 22.04 jammy repos)
- **Resources**: 4 CPU, 4GB RAM, no GPU, network enabled

## Verification Checklist Results (Final Clean Test)

All checks pass on clean (no-cache) environment starts for both tasks:

| Check | predict_iss_pass | add_ground_station |
|-------|:---:|:---:|
| Installation script completes without errors | PASS | PASS |
| Setup script completes without errors | PASS | PASS |
| GPredict process running | PASS | PASS |
| Window titled "Gpredict: Amateur" visible | PASS | PASS |
| Amateur.mod module loaded | PASS | PASS |
| Ground station set to Pittsburgh, PA | PASS | PASS |
| gpredict.cfg created | PASS | PASS |
| 979 satellite .sat files loaded | PASS | PASS |
| TLE cache files present (3 files) | PASS | PASS |
| Window maximized to 1920x1080 | PASS | PASS |
| Tokyo.qth does not exist (clean start) | N/A | PASS |
| Task start state verified via visual_grounding | PASS | PASS |
| Task flow completable end-to-end (evidence) | PASS | PASS |

## Setup Timing

- **Total**: ~65 seconds
- **Environment setup** (pre_start + post_start): ~55 seconds
- **Task-specific hooks** (pre_task): ~10 seconds

## Evidence Screenshots

### predict_iss_pass Task

| File | Description |
|------|-------------|
| `01_gpredict_main_view.png` | GPredict main view with world map, polar plot, satellite detail panel |
| `02_satellite_context_menu.png` | Right-click context menu on satellite: "Show next pass", "Future passes", etc. |
| `03_iss_pass_prediction.png` | "Pass details for ISS (ZARYA) (25544)" dialog with real orbital data |
| `08_final_clean_test.png` | Final clean test start state for predict_iss_pass (Pittsburgh ground station, satellites tracked) |

### add_ground_station Task

| File | Description |
|------|-------------|
| `09_add_gs_start_state.png` | Clean start state for add_ground_station task (Pittsburgh ground station, visual_grounding verified) |
| `10_add_gs_ground_stations_tab.png` | Edit > Preferences > Ground Stations tab showing station and Add/Edit/Delete buttons |
| `11_add_gs_new_station_form.png` | "Edit ground station data" form with Name, Lat, Lon, Alt fields |

### Audit Fix Verification

| File | Description |
|------|-------------|
| `12_pittsburgh_ground_station_fixed.png` | Ground station correctly displays as "Pittsburgh" (not "sample") after config fix |

### Shared Evidence

| File | Description |
|------|-------------|
| `04_preferences_dialog.png` | Edit > Preferences dialog (General > Number Formats) |
| `05_ground_stations_tab.png` | Ground Stations tab in Preferences |
| `06_add_ground_station_dialog.png` | Add New ground station form dialog |
| `07_final_maximized_view.png` | GPredict maximized to full 1920x1080 |

## Log Excerpts (from Final Clean Tests)

### Pre_start Log (install_gpredict.sh)
```
=== Installing GPredict and dependencies ===
Installing GPredict...
Installing utility tools...
Setting up scrot (1.7-1) ...
=== GPredict installation complete ===
```

### Post_start Log (setup_gpredict.sh)
```
=== Setting up GPredict ===
Performing warm-up launch to initialize GPredict...
GPredict window found (WID: 6291457), dismissing any dialogs...
GPredict configuration initialized successfully.
Setting up Pittsburgh ground station as default...
Loading real satellite TLE data from CelesTrak...
=== GPredict setup complete ===
```

### Pre_task Log - predict_iss_pass (setup_task.sh)
```
=== Setting up predict_iss_pass task ===
Pittsburgh ground station QTH file installed.
Stations TLE data loaded.
Launching GPredict...
GPredict window found (WID: ...)
=== predict_iss_pass task setup complete ===
```

### Pre_task Log - add_ground_station (setup_task.sh)
```
=== Setting up add_ground_station task ===
Launching GPredict...
GPredict window found (WID: ...)
=== add_ground_station task setup complete ===
```

## Real Data Sources

| Data | Source | Format | Notes |
|------|--------|--------|-------|
| ISS & Space Stations TLE | CelesTrak `gp.php?GROUP=stations` | NORAD 3-line TLE | Includes ISS (25544), CSS, etc. |
| Amateur Satellites TLE | CelesTrak `gp.php?GROUP=amateur` | NORAD 3-line TLE | AO-73, SO-50, FO-29, etc. |
| Weather Satellites TLE | CelesTrak `gp.php?GROUP=weather` | NORAD 3-line TLE | NOAA, GOES, Metop, etc. |
| Pittsburgh Ground Station | Real coordinates | GPredict .qth | 40.4406°N, 79.9959°W, 230m, ICAO: KPIT |

## Bugs Found and Fixed During Development

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| `gpredict-doc` not found | Package doesn't exist on Ubuntu 22.04 | Removed from install script |
| `setsid DISPLAY=:1` fails | setsid interprets first arg as program name | Moved env vars before setsid |
| Pre-created dirs break first-time init | GPredict skips module copying when config dir exists | Let first-time init run, copy files after |
| `pkill -f gpredict` kills setup script | `-f` matches "setup_gpredict.sh" command line | Changed to `pkill -x gpredict` (exact name match) |
| Ground station shows Copenhagen | Overwriting `sample.qth` was needed (not just adding alongside) | Overwrite `sample.qth` with Pittsburgh data |
| Ground station displays as "sample" | GPredict uses filename (not LOCATION field) for display | Copy as `Pittsburgh.qth`, remove `sample.qth`, update `DEFAULT_QTH` in gpredict.cfg |
| `wmctrl` maximize fails from root | Root can't access ga user's X display | Run `wmctrl` as `su - ga -c "..."` |
