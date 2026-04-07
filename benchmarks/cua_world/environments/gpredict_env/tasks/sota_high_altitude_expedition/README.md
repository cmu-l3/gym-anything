# High-Altitude SOTA Expedition Configuration (`sota_high_altitude_expedition@1`)

## Overview
This task evaluates the agent's ability to configure GPredict for off-grid, portable field operations. The agent must create a high-altitude ground station, build an FM satellite tracking module bound specifically to that station, and modify global application preferences to handle environmental constraints (intense sunlight glare and lack of internet connectivity).

## Rationale
**Why this task is valuable:**
- **UI Preference Modification**: Tests changing global map visuals (`mblue.png`) and background automation behaviors (TLE auto-update), which are previously unexplored mechanical features of GPredict.
- **Module-to-QTH Binding**: Requires locking a specific tracking module to a custom ground station rather than just relying on the default global ground station.
- **Precision Data Entry**: Involves exact coordinate entry for a prominent geographical feature.
- **Real-world relevance**: Setting up ruggedized laptops for offline use in extreme environments is a core task for field researchers and amateur radio operators.

**Real-world Context:** Summits on the Air (SOTA) is an amateur radio program where operators hike to mountain peaks and make contacts. Setting up a portable tracking station on a 14,000-foot peak involves unique challenges: intense sunlight glare makes standard dark screen maps unreadable, and the lack of cellular internet requires the tracking software to automatically cache orbital data (TLEs) whenever it connects to Wi-Fi prior to the hike.

## Task Description

**Goal:** Configure a portable GPredict installation for a high-altitude SOTA activation on Mount Whitney, including offline data caching, glare mitigation, and a peak-specific tracking module.

**Starting State:** GPredict is open with the default configuration (default dark map, no auto-updates, default ground station).

**Expected Actions:**
1. **Create the Summit Ground Station**:
   - Name: `Mt_Whitney`
   - Latitude: 36.5786° N
   - Longitude: 118.2920° W (can be entered as -118.2920)
   - Altitude: 4421 meters

2. **Create a Portable Satellite Module**:
   - Name it `SOTA_FM`.
   - Add the primary FM repeater satellites: **SO-50** (NORAD 27607), **ISS (ZARYA)** (NORAD 25544), and **AO-27** (NORAD 22825).
   - Lock this specific module to the `Mt_Whitney` ground station via the module's properties (do not just change the global default ground station).

3. **Mitigate Screen Glare**:
   - The intense sunlight at 14,000 ft makes the default dark `earth.png` map unreadable. In GPredict's global preferences (Edit > Preferences > Modules > Map), change the default **Map Image** to `mblue.png` (a high-contrast alternative included with GPredict).

4. **Configure Offline Data Caching**:
   - You will have no internet on the mountain. In GPredict's preferences (Edit > Preferences > TLE Update), enable the option to **Update TLE data automatically in the background**. This ensures your laptop caches the latest orbital data whenever it hits a network connection before the hike.

**Final State:** GPredict has a new `SOTA_FM` module displaying passes for Mount Whitney over a high-contrast blue map, and the application is configured to automatically fetch TLE updates in the background.

## Verification Strategy

### Primary Verification: Configuration File Parsing (File-based)
The verification script programmatically reads GPredict's configuration files to ensure the settings were accurately applied without relying purely on image recognition.

1. **QTH File Check**: Reads `~/.config/Gpredict/Mt_Whitney.qth`
   - Parses `LAT`, `LON`, `ALT` and compares against expected values (±0.01 tolerance for coordinates).
2. **Module File Check**: Reads `~/.config/Gpredict/modules/SOTA_FM.mod`
   - Splits the `SATELLITES` string and verifies all 3 required NORAD IDs (27607, 25544, 22825) are present.
   - Checks for `QTHFILE=Mt_Whitney.qth` to ensure proper per-module binding.
3. **Preferences File Check**: Reads `~/.config/Gpredict/gpredict.cfg`
   - Searches the `[MODULE]` section for map background changes (e.g., `MAP_FILE=mblue.png`). The verifier will also accept the change if the agent applies it directly inside the `SOTA_FM.mod` file instead of globally.
   - Searches the `[TLE]` (or equivalent) section for the auto-update flag being enabled (e.g., `AUTO_UPDATE=True`).

### Secondary Verification: Modification Timestamps
Checks the modification timestamp of `gpredict.cfg` and the creation times of the new `.qth` and `.mod` files to ensure "do nothing" agents fail automatically.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Mt_Whitney QTH | 20 | Ground station created with accurate lat/lon/alt parameters |
| SOTA_FM Module Sats | 25 | Module created with exactly the 3 required NORAD IDs |
| Module QTH Binding | 15 | `SOTA_FM` module specifically bound to the `Mt_Whitney` ground station |
| High-Contrast Map | 20 | Global map image changed to `mblue.png` |
| TLE Auto-Update | 20 | Background TLE auto-update flag enabled in global preferences |
| **Total** | **100** | |

**Pass Threshold:** 75 points with the Module and QTH criteria fully met. Partial credit is awarded for missing satellites or partial preference application.