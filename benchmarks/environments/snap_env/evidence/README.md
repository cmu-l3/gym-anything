# SNAP Environment Evidence Documentation

## Environment Overview

- **Application**: ESA SNAP 13 (Sentinel Application Platform)
- **Version**: 13.0.0
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 8GB RAM, network enabled

## Installation Verification

### Pre-start Hook (install_snap.sh)
- SNAP 13.0.0 installed via unattended installer at `/opt/snap`
- Sentinel-1/2/3 Toolboxes and Radar Toolbox included
- GUI automation tools installed (xdotool, wmctrl, scrot)
- 8 real satellite data files downloaded (251MB total)

### Post-start Hook (setup_snap.sh)
- SNAP user config created at `~/.snap/`
- Update check dialog suppressed via warm-up launch
- Desktop shortcut created
- SNAP version check interval set to NEVER

### Data Files Downloaded
All data is **real satellite imagery** from public repositories:

| File | Size | Source | Description |
|------|------|--------|-------------|
| sentinel2a_sample.tif | 5.8MB | Copernicus Sentinel-2A | 3-band (BGR), 10m res, EPSG:32631 |
| sentinel2_b432.tif | 2.2MB | Sentinel-2 B4/B3/B2 | RGB bands |
| sentinel2_tci.tif | 13MB | AWS Sentinel-2 COGs | True Color Image, L2A |
| sentinel2_B04_red.tif | 107MB | AWS Sentinel-2 COGs | Red band (B04), 10m |
| sentinel2_B08_nir.tif | 107MB | AWS Sentinel-2 COGs | NIR band (B08), 10m |
| landsat_multispectral.tif | 9.7MB | opengeos/data | 4-band (SWIR1, NIR, Red, Green) |
| landsat7_rgb.tif | 1.7MB | rasterio test data | Landsat 7 ETM RGB |
| srtm_dem.tif | 5.8MB | opengeos/data | SRTM DEM |

## Tasks

### Task 1: open_and_inspect_geotiff (Easy)
- **Start State**: SNAP open with empty Product Explorer
- **Agent Goal**: Open sentinel2a_sample.tif via File > Open Product, expand product tree, display a band
- **Evidence**: `open_and_inspect_geotiff_start_state.png`, `open_and_inspect_geotiff_verified_start.png`
- **Interactive Test**: Successfully completed. Agent workflow: Alt+F → Enter (Open Product) → type path in File Name field → Enter (navigates to dir) → type filename → Enter (opens file) → handle "Multiple Readers Available" dialog → expand product tree → double-click band_1 → satellite imagery displayed.

### Task 2: create_rgb_composite (Medium)
- **Start State**: SNAP open with landsat_multispectral.tif loaded
- **Agent Goal**: Right-click product, Open RGB Image Window, assign false-color channels
- **Evidence**: `create_rgb_composite_start_state.png`, `create_rgb_composite_verified_start.png` (after script fix)
- **Interactive Test**: Successfully completed. Agent workflow: right-click product in Product Explorer → navigate context menu with keyboard (Down x5 + Enter for "Open RGB Image Window") → RGB dialog appears with default channel assignments → click OK → false-color composite displayed.

### Task 3: compute_ndvi (Medium)
- **Start State**: SNAP open with landsat_multispectral.tif loaded
- **Agent Goal**: Use Raster > Band Maths to compute NDVI from NIR and Red bands
- **Evidence**: `compute_ndvi_start_state.png`, `compute_ndvi_verified_start.png` (after script fix)
- **Interactive Test**: Successfully completed. Agent workflow: click Raster menu → Band Maths... → rename output band to "NDVI" → Edit Expression → type `(B2 - B3) / (B2 + B3)` → expression validates "Ok, no errors." → click OK → NDVI band computed and displayed.

## Verification Checklist

- [x] Installation script (pre_start) completes without errors
- [x] Setup script (post_start) completes without errors
- [x] SNAP 13 is visible and running in all task screenshots
- [x] Real satellite data is loaded (251MB across 8 files)
- [x] Task 1 start state correct: SNAP open, empty Product Explorer (verified via screenshot)
- [x] Task 2 start state correct: SNAP open, landsat_multispectral.tif loaded (verified via screenshot)
- [x] Task 3 start state correct: SNAP open, landsat_multispectral.tif loaded (verified via screenshot)
- [x] No blocking dialogs at task start (update dialog dismissed in warmup)
- [x] Task 1 completable: agent can open file, handle Multiple Readers dialog, expand tree, display band
- [x] Task 2 completable: agent can right-click product, open RGB window, create composite
- [x] Task 3 completable: agent can use Band Maths, enter NDVI expression, compute result
- [x] Setup scripts fixed and re-verified: two-step file open approach works reliably

## Log Snippets

### Post-start log (successful):
```
=== Setting up ESA SNAP configuration ===
Setting up SNAP for user: ga
SNAP setup complete for ga
=== Performing SNAP warm-up launch ===
Waiting for SNAP to start...
SNAP process detected after 0s
Waiting for SNAP window...
SNAP window appeared after 6s
Dismissing SNAP Update dialog if present...
Closing SNAP warm-up instance...
=== SNAP setup complete ===
```

### Task 1 setup log (open_and_inspect_geotiff):
```
=== Setting up open_and_inspect_geotiff task ===
Data file: -rw-r--r-- 1 ga ga 5.8M Feb 15 18:14 /home/ga/snap_data/sentinel2a_sample.tif
Launched SNAP Desktop
Waiting for SNAP process...
SNAP process detected after 0s
Waiting for SNAP window...
SNAP window appeared after 4s
Checking for SNAP startup dialogs...
=== Task ready: SNAP is open. Agent should open the file /home/ga/snap_data/sentinel2a_sample.tif ===
=== open_and_inspect_geotiff task setup complete ===
```

### Task 2 setup log (create_rgb_composite):
```
=== Setting up create_rgb_composite task ===
Data file: -rw-r--r-- 1 ga ga 9.7M Feb 15 18:14 /home/ga/snap_data/landsat_multispectral.tif
Launched SNAP Desktop
Waiting for SNAP process...
SNAP process detected after 0s
Waiting for SNAP window...
SNAP window appeared after 4s
Checking for SNAP startup dialogs...
Opening data file via File menu...
Navigating to data directory...
Opening file...
Checking for Multiple Readers dialog...
Waiting for product to load...
=== Task ready: SNAP is open with Landsat data loaded ===
=== create_rgb_composite task setup complete ===
```

### Task 3 setup log (compute_ndvi):
```
=== Setting up compute_ndvi task ===
Data file: -rw-r--r-- 1 ga ga 9.7M Feb 15 18:14 /home/ga/snap_data/landsat_multispectral.tif
Launched SNAP Desktop
Waiting for SNAP process...
SNAP process detected after 0s
Waiting for SNAP window...
SNAP window appeared after 4s
Checking for SNAP startup dialogs...
Opening data file via File menu...
Navigating to data directory...
Opening file...
Checking for Multiple Readers dialog...
Waiting for product to load...
=== Task ready: SNAP is open with Landsat data loaded ===
=== compute_ndvi task setup complete ===
```

### Java warnings (expected/benign):
```
OpenJDK 64-Bit Server VM warning: Options -Xverify:none and -noverify were deprecated in JDK 13
WARNING: package com.sun.java.swing.plaf.windows not in java.desktop
libEGL warning: DRI2: failed to authenticate
```

## Known Issues and Workarounds

1. **No CLI file opening**: SNAP is a Java/NetBeans app - it does NOT accept file paths as CLI arguments. Files must be opened via File > Open Product menu.
2. **First-run "SNAP Update" dialog**: Appears on initial launch - handled by warm-up in post_start.
3. **Java file chooser two-step open**: SNAP's Open Product dialog uses Java's JFileChooser. When you type a full path (e.g., `/home/ga/snap_data/landsat_multispectral.tif`) and press Enter, it navigates to the directory rather than opening the file. The workaround is: (1) type full path + Enter to navigate to the directory, (2) type just the filename + Enter to open the file.
4. **"Multiple Readers Available" dialog**: When opening GeoTIFF files, SNAP sometimes shows a dialog asking which reader to use. Press Enter to accept the default GeoTIFF reader.
5. **Context menu item spacing**: Menu items like "Open RGB Image Window" and "Open HSV Image Window" are very close together (~14px in 1280x720 scale). Keyboard navigation (Down arrow x N + Enter) is more reliable than mouse coordinate clicking.
6. **libEGL warning**: `libEGL warning: DRI2: failed to authenticate` is a benign GPU driver warning in the VM.
7. **Ubuntu snap conflict**: Ubuntu's `snap` package manager conflicts with ESA SNAP binary name - resolved by installing to `/opt/snap` and creating `esa-snap` symlink.
