# Panoply Environment - Evidence Documentation

## Overview

NASA Panoply is a Java-based desktop application for visualizing netCDF, HDF, and GRIB scientific data files. This environment provides Panoply with real NOAA/NCEP climate data for visualization tasks.

## Environment Setup Verification

### Installation (pre_start)
- **Panoply 5.3.1** installed from Wayback Machine archive (NASA GISS site used as primary, Wayback Machine as fallback)
- **Java 11** (OpenJDK 11.0.30) installed via apt
- **5 real NOAA netCDF data files** downloaded from NOAA PSL (downloads.psl.noaa.gov)

### Data Files (Real NOAA Data)
| File | Source | Size | Description |
|------|--------|------|-------------|
| air.mon.ltm.nc | NCEP/NCAR Reanalysis | 642KB | Global air temperature monthly long-term means |
| sst.ltm.1991-2020.nc | NOAA OI SST v2 | 3.3MB | Sea surface temperature climatology |
| prate.sfc.mon.ltm.nc | NCEP/NCAR Reanalysis | 710KB | Precipitation rate monthly long-term means |
| slp.mon.ltm.nc | NCEP/NCAR Reanalysis | 540KB | Sea level pressure monthly long-term means |
| pres.mon.ltm.nc | NCEP/NCAR Reanalysis | 588KB | Surface pressure monthly long-term means |

All data is real climate reanalysis data from NOAA Physical Sciences Laboratory. Attribution: "NCEP Reanalysis data provided by the NOAA/OAR/ESRL PSL, Boulder, Colorado, USA, from their website at https://psl.noaa.gov"

### Post-Start Setup
- Warm-up launch of Panoply to initialize preferences and dismiss first-run dialogs
- Desktop launcher created at /home/ga/Desktop/Panoply.desktop
- All 5 data files verified by size check

---

## Task 1: change_map_projection

**Description**: Change the map projection of a geo-mapped air temperature plot from Equirectangular to Orthographic.

### Evidence Screenshots

1. **final_clean_test_task1_start.png** — Final clean test start state. Shows the Equirectangular projection (flat map) with NCEP air temperature data displayed. Plot Controls panel shows "Show: Map Projection" with "Projection: Equirectangular". Confirmed correct via visual_grounding MCP tool.

2. **clean_test_task1_after_projection_change.png** — After manually changing projection to Orthographic. The plot now shows a globe view of Earth with temperature data. Plot Controls shows "Projection: Orthographic".

3. **panoply_proj_dropdown.png** — Shows the projection dropdown opened, listing 200+ available projections (Equirectangular highlighted).

4. **panoply_map_proj.png** — Shows the Plot Controls panel in "Map Projection" mode with the Equirectangular dropdown visible.

### Task Start State (Verified via visual_grounding)
- **Windows open**: Panoply — Sources, air in air.mon.ltm, Plot Controls
- **Plot Controls**: Shows "Map Projection" tab with "Projection: Equirectangular"
- **Plot content**: Global air temperature color map with Equirectangular (flat) projection
- **Real data visible**: NCEP/NCAR Reanalysis long-term mean air temperature at sigma level 0.995
- **Color scale**: -37.5°C (blue) to 33.6°C (red)

### How an Agent Would Complete This Task
1. Locate the "Projection:" dropdown in the Plot Controls panel (left side)
2. Click the dropdown to open it
3. Type "Orth" to jump to Orthographic, or scroll to find it
4. Click "Orthographic" to select it
5. The plot automatically updates to show the globe in Orthographic (spherical) view

### Task 1 Log Excerpt (from `task1_pre_task.log`)
```
=== Setting up change_map_projection task ===
Data file found: /home/ga/PanoplyData/air.mon.ltm.nc (657356 bytes)
Launching Panoply with air temperature data...
Panoply window detected after 2s
Selecting 'air' variable...
Waiting for plot to render...
=== Task setup complete ===
Task: Change the map projection from Equirectangular to Orthographic
Current windows:
0x01a0002e  0 ga-base Panoply — Sources
0x01a000c2  0 ga-base air in air.mon.ltm
0x01a000c9  0 ga-base Plot Controls
```

---

## Task 2: export_plot_as_image

**Description**: Export a geo-mapped sea surface temperature plot as a PNG image to `/home/ga/Documents/PanoplyExports/sst_plot.png`.

### Evidence Screenshots

1. **clean_test_task2_start.png** — Final clean test start state. Shows SST data plot "Long Term Mean Monthly Mean of Sea Surface Temperature" with Equirectangular projection. Confirmed correct via visual_grounding MCP tool.

2. **clean_test_task2_save_dialog.png** — Shows the "Save as..." dialog opened via Ctrl+Shift+S. Dialog contains: file browser showing Documents/PanoplyExports folders, filename field ("sst_in_sst.ltm.1991-2020.png"), format selector (PNG Image), Save/Cancel buttons.

3. **panoply_file_menu2.png** — Shows the File menu with "Save Image" (Ctrl+S) and "Save Image As..." (Ctrl+Shift+S) options visible.

### Task Start State (Verified via visual_grounding)
- **Windows open**: Panoply — Sources, sst in sst.ltm.1991-2020, Plot Controls
- **Plot content**: Global sea surface temperature color map
- **Real data visible**: NOAA OI SST v2 long-term mean (1991-2020 climatology)
- **Color scale**: -1.8°C (blue) to 30.7°C (red)
- **Export directory**: /home/ga/Documents/PanoplyExports/ exists and is empty

### How an Agent Would Complete This Task
1. Focus the SST plot window ("sst in sst.ltm.1991-2020")
2. Open File > Save Image As... (or press Ctrl+Shift+S)
3. In the Save dialog, navigate to Documents > PanoplyExports
4. Clear the filename field and type "sst_plot.png"
5. Ensure format is "PNG Image"
6. Click Save
7. File is saved at /home/ga/Documents/PanoplyExports/sst_plot.png

### Task 2 Log Excerpt (from `task2_pre_task.log`)
```
=== Setting up export_plot_as_image task ===
Data file found: /home/ga/PanoplyData/sst.ltm.1991-2020.nc (3441836 bytes)
Launching Panoply with SST data...
Panoply window detected after 2s
Selecting 'sst' variable...
Waiting for plot to render...
SST plot window focused: 0x01a000c6
=== Task setup complete ===
Task: Export the SST plot as PNG to /home/ga/Documents/PanoplyExports/sst_plot.png
Current windows:
0x01a0002e  0 ga-base Panoply — Sources
0x01a000c6  0 ga-base sst in sst.ltm.1991-2020
0x01a000cd  0 ga-base Plot Controls
```

---

## Shared Log Excerpts

### pre_start.log (Installation) — from `task1_pre_start.log`
```
=== Installing NASA Panoply ===
Installing Java JDK...
openjdk version "11.0.30" 2026-01-20
Downloading NASA Panoply...
NASA GISS unreachable, trying Wayback Machine...
Downloaded Panoply 5.3.1 from Wayback Machine
Extracting Panoply...
Installing Panoply to /opt/PanoplyJ...
Downloading real NOAA netCDF data files...
Downloading NCEP air temperature data...
Downloading NOAA SST data...
Downloading NCEP precipitation rate data...
Downloading NCEP sea level pressure data...
Downloading NCEP surface pressure data...
Downloaded data files:
total 5.8M
-rw-r--r-- 1 ga ga 642K air.mon.ltm.nc
-rw-r--r-- 1 ga ga 710K prate.sfc.mon.ltm.nc
-rw-r--r-- 1 ga ga 588K pres.mon.ltm.nc
-rw-r--r-- 1 ga ga 540K slp.mon.ltm.nc
-rw-r--r-- 1 ga ga 3.3M sst.ltm.1991-2020.nc
=== NASA Panoply installation complete ===
Panoply installed at: /opt/PanoplyJ
Data files at: /home/ga/PanoplyData
```

### post_start.log (Setup) — from `task1_post_start.log`
```
=== Setting up NASA Panoply environment ===
Checking data files...
  Found: air.mon.ltm.nc (657356 bytes)
  Found: sst.ltm.1991-2020.nc (3441836 bytes)
  Found: prate.sfc.mon.ltm.nc (726425 bytes)
  Found: slp.mon.ltm.nc (552234 bytes)
  Found: pres.mon.ltm.nc (602061 bytes)
Performing warm-up launch of Panoply...
Panoply window detected after 2s
Closing warm-up Panoply instance...
=== NASA Panoply setup complete ===
```

---

## Evidence Files Index

### Screenshots (Final Clean Test)
| File | Task | Description |
|------|------|-------------|
| `final_clean_test_task1_start.png` | Task 1 | Task start state: air temp plot, Equirectangular projection |
| `clean_test_task1_after_projection_change.png` | Task 1 | After projection change: Orthographic globe view |
| `clean_test_task2_start.png` | Task 2 | Task start state: SST plot, ready for export |
| `clean_test_task2_save_dialog.png` | Task 2 | Save Image As dialog with PNG format selected |

### Screenshots (Interactive Testing)
| File | Description |
|------|-------------|
| `panoply_launch.png` | Initial Panoply launch with air.mon.ltm.nc loaded |
| `panoply_after_dblclick.png` | Create Plot dialog after double-clicking air variable |
| `panoply_plot_created.png` | Geo-mapped air temperature plot created |
| `panoply_map_proj.png` | Plot Controls in Map Projection mode |
| `panoply_proj_dropdown.png` | Projection dropdown showing 200+ options |
| `panoply_orthographic.png` | Plot after switching to Orthographic projection |
| `panoply_file_menu2.png` | File menu showing Save Image / Save Image As options |
| `clean_test_save_dialog.png` | Save dialog from earlier testing |

### Log Files
| File | Task | Description |
|------|------|-------------|
| `task1_pre_start.log` | Task 1 | Installation log (Panoply + NOAA data download) |
| `task1_post_start.log` | Task 1 | Setup log (warm-up launch, data verification) |
| `task1_pre_task.log` | Task 1 | Task setup log (air variable selected, plot created) |
| `task2_pre_start.log` | Task 2 | Installation log |
| `task2_post_start.log` | Task 2 | Setup log |
| `task2_pre_task.log` | Task 2 | Task setup log (sst variable selected, plot created) |

---

## Verification Checklist

- [x] Installation script completes without errors (both task runs)
- [x] Setup script completes without errors (both task runs)
- [x] Application is visible in screenshot (Panoply windows appear)
- [x] Application is in correct initial state with real data loaded
- [x] Task 1 setup runs without errors — creates air temperature plot with Equirectangular projection
- [x] Task 1 start state verified via visual_grounding — "Projection: Equirectangular" confirmed
- [x] Task 1 completable — projection dropdown opens, Orthographic selectable, plot updates to globe view
- [x] Task 2 setup runs without errors — creates SST plot, export directory prepared
- [x] Task 2 start state verified via visual_grounding — SST plot visible, correct window title "sst in sst.ltm.1991-2020"
- [x] Task 2 completable — File > Save Image As opens save dialog with PNG format, filename field, folder navigation
- [x] Real NOAA data used (no synthetic/mock data) — NCEP/NCAR Reanalysis and NOAA OI SST v2
- [x] Sufficient evidence that both tasks are completable end-to-end
