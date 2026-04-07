# Atmospheric Diurnal Tracking & Visualization Setup (`atmospheric_diurnal_tracking_setup@1`)

## Overview
This task evaluates the agent's ability to configure advanced map visualization preferences and establish a tracking module for a specific scientific satellite constellation. Unlike basic tracking tasks, this requires modifying global UI settings to display the day/night terminator and extended orbital ground tracks, which are critical features for researchers studying diurnal (day/night) environmental phenomena.

## Rationale
**Why this task is valuable:**
- Tests modification of **global map visualization preferences** (terminator line, orbit track lengths) — a UI interaction not tested in previous tasks.
- Tests configuration of application-wide **time localization settings** (forcing UTC).
- Requires building a complete, multi-satellite tracking module from scratch using specific catalog numbers.

**Real-world Context:** Atmospheric scientists tracking Radio Occultation (RO) satellites must visualize the day/night terminator line. Because ionospheric electron density changes drastically at the day/night boundary (directly affecting the GPS signal bending that these satellites measure), seeing the constellation's position relative to the terminator is essential for observation planning.

## Task Description

**Goal:** Configure GPredict to track the 6 COSMIC-2/FORMOSAT-7 radio occultation satellites from a new Taipei ground station, and modify the map preferences to display the terminator line and multi-orbit ground tracks.

**Starting State:** GPredict is open with default settings (Pittsburgh ground station, basic Amateur module). 

**Expected Actions:**

1. Create a new ground station for the Taiwan Central Weather Administration (**Taipei_CWA**):
   - Latitude: 25.0380° N
   - Longitude: 121.5030° E
   - Altitude: 9 meters

2. Set **Taipei_CWA** as the default ground station in the application preferences (Edit > Preferences > General > Ground Stations).

3. Set the global time format to **UTC** (Edit > Preferences > General > Date and Time).

4. Configure the global Map View preferences (Edit > Preferences > Modules > Map):
   - Enable the **terminator line** (to visualize the day/night shadow boundary).
   - Set the **ground track** to display exactly **2 orbits** ahead.

5. Create a new tracking module named **COSMIC-2**.

6. Add the 6 radio occultation satellites to the **COSMIC-2** module. You can find them by searching their NORAD IDs:
   - FORMOSAT-7 FM1 (NORAD 44327)
   - FORMOSAT-7 FM2 (NORAD 44328)
   - FORMOSAT-7 FM3 (NORAD 44329)
   - FORMOSAT-7 FM4 (NORAD 44330)
   - FORMOSAT-7 FM5 (NORAD 44331)
   - FORMOSAT-7 FM6 (NORAD 44332)

7. Close all preference dialogs and ensure your newly created **COSMIC-2** module is open and visible, clearly showing the map view.

**Final State:** A new `Taipei_CWA.qth` ground station exists and is set as the default. A `COSMIC-2.mod` module exists containing the 6 satellites. The main GPredict UI displays the map with the shaded night terminator and extended ground tracks.

## Verification Strategy

### Primary Verification: Configuration File State Check
The verifier programmatically parses GPredict's configuration files (which use a standard INI/glib keyfile format) to detect precise state changes:
- Reads `~/.config/Gpredict/Taipei_CWA.qth` to verify coordinates.
- Reads `~/.config/Gpredict/modules/COSMIC-2.mod` to ensure the `SATELLITES` string contains all 6 specified NORAD IDs.
- Reads `~/.config/Gpredict/gpredict.cfg` to verify global preference changes.

### Secondary Verification: VLM Visual Check
A Vision-Language Model samples the trajectory frames and final screenshot to verify that:
1. The map view is visible.
2. The terminator shadow (the dark overlay indicating nighttime on Earth) is visibly rendered.
3. Satellite ground tracks are rendered and extending well ahead of the satellites (visually corresponding to multiple orbits).

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Taipei Ground Station | 20 | `Taipei_CWA.qth` exists with accurate Lat/Lon/Alt |
| Default QTH Updated | 10 | `gpredict.cfg` reflects Taipei as default station |
| Module Populated | 30 | `COSMIC-2.mod` contains all 6 FORMOSAT-7 NORAD IDs (5 pts each) |
| Terminator Enabled | 15 | Global preferences updated to show terminator line |
| Tracks Configured | 15 | Global preferences updated to show 2 ground track orbits |
| UTC Time Configured | 10 | Time format set to UTC in preferences |
| **Total** | **100** | |

**Pass Threshold:** 70 points, including at least partial points in the Module Populated and Terminator Enabled categories.