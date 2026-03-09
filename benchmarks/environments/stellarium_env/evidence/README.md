# Stellarium Environment - Evidence Documentation

## Verification Checklist

### Installation (pre_start hook)
- [x] `install_stellarium.sh` completes without errors
- [x] Stellarium 0.20.4 (Qt5) installed from Ubuntu universe repo
- [x] Mesa/OpenGL packages installed for llvmpipe software rendering
- [x] `LIBGL_ALWAYS_SOFTWARE=1` set globally in `/etc/environment`
- [x] Python astropy package installed for data processing

### Setup (post_start hook)
- [x] `setup_stellarium.sh` completes without errors
- [x] Config.ini copied to `~/.stellarium/` with `[init_location] landscape_name = guereins`
- [x] Launch script created with Mesa environment variables
- [x] Warm-up launch succeeds: window found
- [x] Warm-up instance properly killed (single instance after task setup)

### Application State
- [x] Stellarium visible in all task screenshots
- [x] Default view: atmosphere on, ground visible, stars in night sky
- [x] Running at ~22-27 FPS with llvmpipe software rendering
- [x] Single process, single window

### All Three Tasks Verified (via visual_grounding MCP tool)

#### Task 1: observe_solar_eclipse
- [x] VM boots and Stellarium launches successfully
- [x] Screenshot verified: night sky with stars, Sirius labeled
- [x] Start state: default view with atmosphere/ground enabled
- [x] Agent goal: set location to Hopkinsville KY, date to Aug 21 2017, observe totality
- See `task_observe_solar_eclipse_start.png`

#### Task 2: locate_planet_conjunction
- [x] VM boots and Stellarium launches successfully
- [x] Screenshot verified: night sky visible, star labels present
- [x] Start state: planet labels toggled on, default view
- [x] Agent goal: set date to Dec 21 2020, location to Paranal, find Jupiter-Saturn conjunction
- See `task_locate_planet_conjunction_start.png`

#### Task 3: configure_deep_sky_observation
- [x] VM boots and Stellarium launches successfully
- [x] Screenshot verified: night sky with atmosphere ON, ground visible, no constellation lines
- [x] Start state: default view with atmosphere/ground enabled, constellations disabled
- [x] Agent goal: set location to Mauna Kea, disable atmosphere/ground, enable constellations, find M31
- See `task_configure_deep_sky_observation_start.png`

### UI Interaction Verification (via visual_grounding)
- [x] Location dialog (F6) opens with world map, coordinates, city search
  - See `location_dialog_f6.png`
- [x] Date/Time dialog (F5) opens with year/month/day/hour/minute/second controls
  - See `ui_datetime_dialog.png`
- [x] Search dialog (Ctrl+F) opens with object search, SIMBAD tab, Greek letter buttons
  - See `ui_search_dialog.png`
- [x] Keyboard shortcuts work: atmosphere (a), ground (g), constellation lines (c)
  - See `keyboard_shortcuts_working.png`
- [x] M31 (Andromeda Galaxy) findable via search
  - See `m31_search_result.png`

### Real Data Sources
- `messier_catalog.json`: 33 Messier objects from NASA/IPAC Extragalactic Database (NED) and SIMBAD
- `historical_eclipses.json`: 5 total solar eclipses (2017-2026) from NASA Eclipse Database
- `observatory_locations.json`: 12 observatories from IAU Minor Planet Center observatory codes

## Screenshots

### Task Start States (verified with visual_grounding MCP)
1. `task_observe_solar_eclipse_start.png` - Stellarium default sky view for solar eclipse task
2. `task_locate_planet_conjunction_start.png` - Stellarium with planet labels for conjunction task
3. `task_configure_deep_sky_observation_start.png` - Stellarium default view for deep sky task

### UI Dialogs (verified with visual_grounding MCP)
4. `ui_datetime_dialog.png` - Date/Time dialog (F5) showing date/time fields
5. `ui_search_dialog.png` - Search dialog (Ctrl+F) with SIMBAD tab

### Earlier Evidence
6. `configure_deep_sky_observation_start.png` - Initial deep sky task verification
7. `keyboard_shortcuts_working.png` - Display toggles working (atmosphere off, ground off, constellations on)
8. `m31_search_result.png` - M31 found via Ctrl+F search
9. `location_dialog_f6.png` - Location dialog with world map
10. `datetime_dialog_f5.png` - Date/Time dialog

## Boot Timing
- Total setup: ~103 seconds per task
- Pre-start (install): ~50 seconds
- Post-start (warm-up): ~38 seconds
- Task setup: ~14 seconds

## Known Issues
- Location config in `config.ini` uses `Pittsburgh, Pennsylvania, United States` format which Stellarium doesn't parse; defaults to Paris. This is cosmetic - all tasks use the Location dialog (F6) to change location as part of the task.
- The `[init_location] landscape_name = guereins` key is CRITICAL - without it, Stellarium crashes with a NULL pointer dereference in `LandscapeMgr::setFlagLandscape()`.
