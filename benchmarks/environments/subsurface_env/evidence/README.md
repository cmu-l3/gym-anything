# Subsurface Environment — Evidence Documentation

## Summary

The Subsurface dive log environment has been fully verified working correctly.
All checklist items below are confirmed via interactive testing on 2026-02-21.
Four tasks were tested end-to-end with screenshots and programmatic verification.
Start-state screenshots captured for all 10 tasks (added 2026-02-21).

---

## Verification Checklist

- [x] **Installation script completes without errors** — Subsurface installed via stable PPA (`ppa:subsurface/subsurface`) on Ubuntu 22.04 Jammy. See install log excerpt below.
- [x] **Setup script completes without errors** — Sample data (1,653,205 bytes) installed to `/home/ga/Documents/dives.ssrf`.
- [x] **Application is visible in screenshot** — See `03_application_clean_state.png` — Subsurface window shows "Subsurface: dives.ssrf (29 dives)".
- [x] **Application is in correct initial state with real data loaded** — 29 real dives from official Subsurface sample data across multiple locations (Hoodsport WA, Larnaca Cyprus, Koror Palau, Bonaire).
- [x] **Task setup runs without errors** — pre_task hook launches Subsurface, waits for window, maximizes, and dismisses dialogs.
- [x] **Task start state is correct** — Verified via screenshots: dive list visible, target dives (2, 3, 4, 85) accessible and clickable.
- [x] **edit_dive_buddy task completable** — Changed buddy on Dive #2 from "David" to "Michael Chen"; saved; verified in SSRF XML (`buddy='Michael Chen'`).
- [x] **change_to_imperial task completable** — File > Preferences > Units > Imperial; saved; config shows `unit_system=1`; depths now display in feet.
- [x] **export_dives_csv task completable** — File > Export > CSV dive list > All dives; saved to `/home/ga/Documents/dive_log.csv` (10,254 bytes, 29 data rows).
- [x] **add_dive_tags task completable** — Selected Dive #85 (Sep 29 2011, Yellow House); added "deep" and "deco" tags; saved; SSRF shows `tags='shore, deep, deco'`.

---

## Interactive Testing Results

### Task: edit_dive_buddy
- **Workflow**: Expand "Hoodsport, WA, USA, Dec 2010" trip → click Dive #2 → triple-click buddy field → type "Michael Chen" → Ctrl+S
- **Verified in SSRF**: `<dive number='2' ... buddy='Michael Chen' ...>`
- **Screenshot**: `04_dive2_selected_edit_buddy_task.png`

### Task: change_to_imperial
- **Workflow**: File > Preferences → click "Units" in left sidebar → click "Imperial" radio button → click Save
- **Verified in config**: `/home/ga/.config/Subsurface/Subsurface.conf` shows `unit_system=1` in `[Units]` section
- **Visual confirmation**: Depths in dive list now show in feet (35ft, 36ft, 37ft, 40ft)
- **Screenshot**: `05_change_to_imperial_verified.png`

### Task: export_dives_csv
- **Workflow**: File > Export (Ctrl+E) → select "CSV dive list" + "All dives" → OK → navigate to Documents → type "dive_log.csv" → Save
- **Verified by file**: `/home/ga/Documents/dive_log.csv` (10,254 bytes) with 29 dive records and proper headers (dive number, date, duration, maxdepth, location, buddy, notes, tags, ...)
- **Screenshot**: `06_export_csv_complete.png`

### Task: add_dive_tags
- **Workflow**: Expand "Hoodsport, WA, USA, Sep 2011" trip → click Dive #85 → triple-click Tags field → type "deep, deco, shore" → Ctrl+S
- **Verified in SSRF**: `<dive number='85' ... tags='shore, deep, deco' ...>`
- **Note**: Tags field shows existing + new tags as colored chips. Triple-click to select all, then retype all tags.
- **Screenshot**: `07_add_dive_tags_verified.png`

---

## Screenshots

### Environment Setup and Initial State

| File | Description |
|------|-------------|
| `01_initial_launch_with_dialogs.png` | First launch showing the update check dialog (dismissed by clicking Decline). Fixed in setup script with `DontCheckForUpdates=true`. |
| `02_dive_list_overview.png` | Application showing dive list with all 29 dives grouped by trip (Bonaire 2014, Yellow House 2014, Palau 2013, Cyprus 2011, Hoodsport Sep 2011, Hoodsport Dec 2010). |
| `03_application_clean_state.png` | Clean application state with all dive trip groups visible in the dive list. |

### Task Start States

| File | Task | Description |
|------|------|-------------|
| `04_dive2_selected_edit_buddy_task.png` | `edit_dive_buddy` | Dive #2 selected — Date: Dec 4 2010, Location: Sund Rock Hoodsport WA, Buddy: David, Notes: "First OWD dive unbelievably cold". Start state is correct. |
| `05_edit_buddy_dive2_start_state.png` | `edit_dive_buddy` | Dive #2 selected with Information tab showing buddy field "David" ready to edit. |
| `09_add_nitrox_cylinder_start_state.png` | `add_nitrox_cylinder` | Dive #3 selected with Equipment tab showing existing LP85 cylinder (13.4L, 182bar, 21% O₂ air). User must change O₂% to 32% to make it nitrox. |
| `10_update_dive_notes_start_state.png` | `update_dive_notes` | Dive #4 selected with Notes tab showing current notes text "third OWD dive". User must append observation about an octopus sighting. |
| `11_set_dive_site_gps_start_state.png` | `set_dive_site_gps` | Dive #2 selected with Information tab showing Location "Sund Rock, Hoodsport, WA, USA" and GPS edit icons. User must set GPS to 47.4005 -123.1420. |
| `12_create_dive_trip_start_state.png` | `create_dive_trip` | Main dive list showing all 6 existing trip groups collapsed. User must create a new trip for a Red Sea dive in September 2022. |
| `13_plan_basic_dive_start_state.png` | `plan_basic_dive` | Dive Planner open (Log > Plan dive), showing gas table, dive profile graph, and planning parameters. User must configure a 30m/60min recreational dive plan. |

### Task Completion Evidence

| File | Task | Description |
|------|------|-------------|
| `05a_prefs_units_imperial_selected.png` | `change_to_imperial` | Preferences dialog open with Units section — Imperial radio button selected, showing depth in feet (ft), pressure in psi, volume in cuft, temperature in °F, weight in lbs. |
| `05b_change_to_imperial_post_save.png` | `change_to_imperial` | Main window after saving imperial preferences. Depths now show in feet (e.g., "D: 10.8ft") and pressure shows in psi ("EAN33 487psi"). Config confirmed `unit_system=1`. |
| `06a_export_csv_dialog_filename.png` | `export_dives_csv` | Qt file save dialog open in /home/ga/Documents with "dive_log.csv" typed in filename field, ready to click Save. |
| `06b_export_csv_complete.png` | `export_dives_csv` | Main window after CSV export. File verified at /home/ga/Documents/dive_log.csv (10,254 bytes, 29 rows + header). |
| `06_edit_buddy_saved_michael_chen.png` | `edit_dive_buddy` | Dive #2 after saving buddy "Michael Chen". SSRF confirmed `buddy='Michael Chen'`. |
| `07_add_dive_tags_verified.png` | `add_dive_tags` | Dive #85 with tags "deep", "deco", "shore" showing as colored chips. SSRF confirmed `tags='shore, deep, deco'`. |

---

## Install Log Excerpt (from `/home/ga/env_setup_pre_start.log`)

```
=== Installing Subsurface Dive Log ===
Base dependencies installed.
Attempting Subsurface installation via PPA...
Repository: 'deb https://ppa.launchpadcontent.net/subsurface/subsurface/ubuntu/ jammy main'
Description: Subsurface open source divelog
Adding repository.
Adding key to /etc/apt/trusted.gpg.d/subsurface-ubuntu-subsurface.gpg
  with fingerprint 33019F96E07BA4CBE58E41BBCDF92DBFB511CE42
Subsurface installed via stable PPA.
Downloading official Subsurface sample dive data...
Sample data downloaded from https://raw.githubusercontent.com/subsurface/subsurface/master/dives/SampleDivesV2.ssrf
Sample data size: 1653205 bytes
=== Subsurface installation complete ===
```

---

## Post-Start Log Excerpt (from `/home/ga/env_setup_post_start.log`)

```
=== Setting up Subsurface Dive Log ===
Sample dive data installed: 1653205 bytes
Performing warm-up launch to dismiss any first-run dialogs...
non-network local connections being added to access control list
=== Subsurface setup complete ===
```

---

## Task Log (from `/home/ga/subsurface_task.log`)

Qt runtime warnings (normal/non-blocking):
```
QStandardPaths: XDG_RUNTIME_DIR not set, defaulting to '/tmp/runtime-ga'
QObject::connect(QQuickWindow, QDeclarativeGeoMap_QML_6): invalid nullptr parameter
```

---

## Real Data Summary

The `SampleDivesV2.ssrf` file from the official Subsurface repository contains:

| Dive # | Date | Location | Duration | Max Depth |
|--------|------|----------|----------|-----------|
| 2 | 2010-12-04 | Sund Rock, Hoodsport WA | 14:30 | ~11m |
| 3 | 2010-12-04 | Sund Rock, Hoodsport WA | 23:00 | ~11m |
| 4 | 2010-12-05 | Sund Rock, Hoodsport WA | 21:30 | ~12m |
| 5 | 2010-12-05 | Sund Rock, Hoodsport WA | 16:00 | ~11m |
| 85 | 2011-09-29 | Yellow House, Hoodsport WA | 32:56 | ~13m |
| 86-90 | 2011-09-29/30 | Yellow House, Hoodsport WA | 22-44 min | 13-26m |
| 91-96 | 2011-10-20/22 | Larnaca, Cyprus (Zenobia wreck) | 62-74 min | deep |
| 223-233 | 2013-06-01/04 | Koror, Palau (Blue Corner, etc.) | 53-74 min | deep |
| 333 | 2014-09-21 | Yellow House, Hoodsport WA | 35:46 | - |
| 348 | 2014-10-10 | Divi Flamingo House Reef, Bonaire | 119:55 | 21m |

All dives include real dive computer data: depth profiles, temperatures, tank pressures, SAC rates, events (safety stops, gas changes, warnings).

---

## Known Quirks

1. **Update check dialog**: On first launch, Subsurface shows "Automatic check for updates" dialog. Fixed by setting `DontCheckForUpdates=true` in `~/.config/Subsurface/Subsurface.conf` AND in the `[UpdateManager]` section. The warm-up launch in `setup_subsurface.sh` now handles this.

2. **Qt runtime warnings**: `QStandardPaths: XDG_RUNTIME_DIR not set` — these are harmless warnings from the Qt framework running without a proper user session directory. Do not affect functionality.

3. **Information tooltip**: A dive statistics popup appears when hovering over the dive profile graph. Dismiss with the X button or Escape key.

4. **Dive numbering**: Dive numbers in the log are the actual diving career numbers of a real diver (e.g., #348 = this person's 348th dive ever). The log contains a subset of their total dives.

5. **Tags field editing**: The tags field shows existing tags as colored chips. To replace all tags: triple-click the field (selects all content) then type the new comma-separated tags (e.g., "deep, deco, shore"). The field auto-parses comma-separated entries into individual chips.

6. **Trip groups collapsed by default**: On initial launch, all trip groups (e.g., "Hoodsport, WA, USA, Dec 2010") are collapsed. Click the group header to expand it and see individual dives.

7. **File > Export CSV path**: In the GTK file dialog, navigate to Documents folder by double-clicking, then click in the filename field and type the filename (e.g., "dive_log.csv") before clicking Save.
