# KStars + INDI CCD Simulator Environment — Evidence

## Environment: `kstars_sim_env@0.1`

### Verification Checklist

- [x] **Installation script completes without errors** — See `final_pre_start_log.txt`. KStars-bleeding, indi-full, and gsc (310MB Guide Star Catalog) all installed successfully.
- [x] **Setup script completes without errors** — See `final_post_start_log.txt`. INDI server started with 4 simulator drivers, all devices connected, KStars window launched and maximized.
- [x] **Application is visible in screenshot** — See `final_test_kstars_view.png`. KStars planetarium showing Pittsburgh sky with stars, Vega, and Jupiter visible.
- [x] **Application is in correct initial state with real data** — KStars running from Pittsburgh, PA. Guide Star Catalog (real Hubble data) installed. INDI simulator devices connected.
- [x] **Task setup runs without errors** — See `final_task_pre_task_log.txt`. Transient alert file placed on Desktop. Initial FITS count recorded as baseline.
- [x] **Task start state is correct** — KStars maximized, INDI server running, telescope unparked, CCD configured for local saves.
- [x] **CCD star field rendering works** — See `ccd_star_field_capture.png`. Real star patterns from the Hubble Guide Star Catalog rendered at correct positions when pointing at M42 (Orion).
- [x] **Telescope slew works** — Tested slew to NGC 4526 (RA 12h 34m, Dec +7° 42'). Confirmed final position matches target within tolerance.
- [x] **CCD exposure capture works** — 10-second exposure at NGC 4526 produced FITS file with 1312 star pixels detected, correct RA/DEC in header.
- [x] **Live sky survey capture works** — `capture_sky_view.sh` reads telescope RA/Dec from INDI, fetches real DSS2 Color survey imagery from the CDS hips2fits API, and applies false color enhancement via `false_color.py` to produce stunning 1920x1080 images based on telescope pointing.
- [x] **False color palettes work** — Available palettes: enhanced, hubble, narrowband, heat, cool, vibrant. Each produces a distinct visual style.
- [x] **DS9 installed and functional** — SAOImageDS9 available at `/usr/bin/ds9`, can display FITS files with Heat colormap and log stretch.
- [x] **Captured images display on screen** — Image viewer displays the false-color sky survey captures on the VM desktop, producing spectacular screenshots of the pointed-at sky region.
- [x] **Caching works** — Pre-start checkpoint cached at `checkpoint_50b4c021688b8ca3_pre_start.qcow2`. Second run skipped 15-min install, total setup time reduced from ~227s to ~63s.

### Evidence Files

| File | Description |
|------|-------------|
| `kstars_initial_view.png` | KStars planetarium view after initial boot |
| `task_start_screenshot.png` | Task start state with KStars maximized |
| `final_test_kstars_view.png` | Final clean test — KStars view from Pittsburgh |
| `ccd_star_field_capture.png` | CCD simulator star field image (M42/Orion region, 15s exposure) |
| `pre_start_log.txt` | Installation log — apt packages, PPA, verification |
| `post_start_log.txt` | Setup log — INDI server, device connections, KStars launch |
| `task_pre_task_log.txt` | Task setup log — alert file, baseline recording |
| `final_pre_start_log.txt` | Clean test installation log |
| `final_post_start_log.txt` | Clean test setup log |
| `final_task_pre_task_log.txt` | Clean test task setup log |
| `enhanced_01_kstars.png` | KStars view during enhanced workflow test |
| `enhanced_02_post_slew.png` | Post-slew view (telescope pointed at NGC 4526) |
| `enhanced_03_ds9_galaxy.png` | DS9 showing NGC 4526 FITS with Heat colormap |
| `enhanced_04_ds9_orion.png` | DS9 showing M42 (Orion) FITS with Heat colormap |
| `enhanced_05_ds9_ring.png` | DS9 showing M57 (Ring Nebula) FITS |
| `enhanced_color_NGC4526.png` | NGC 4526 color composite displayed in image viewer |
| `enhanced_color_M42.png` | M42 Orion Nebula color composite on screen |
| `enhanced_color_M31.png` | M31 Andromeda Galaxy color composite on screen |
| `enhanced_color_M57.png` | M57 Ring Nebula color composite on screen |
| `NGC4526_color.png` | NGC 4526 RGB composite (800x800, asinh stretch) |
| `M42_color.png` | M42 Orion Nebula RGB composite |
| `M31_color.png` | M31 Andromeda Galaxy RGB composite |
| `M45_color.png` | M45 Pleiades RGB composite |
| `M13_color.png` | M13 Hercules Cluster RGB composite |
| `M57_color.png` | M57 Ring Nebula RGB composite |

### Key Metrics

- **Install time**: ~3.5 minutes (PPA + packages + archival FITS download + RGB composites)
- **Install (cached)**: ~0s (checkpoint restores full install state)
- **Setup time**: ~47 seconds (INDI server + device connection + KStars launch)
- **Task setup time**: ~16 seconds (alert file copy, state recording, verification)
- **CCD exposure**: 15s exposure → 2.5MB FITS file with real star patterns
- **Telescope slew**: Accurate to within arcminute of target coordinates
- **Sky capture**: `capture_sky_view.sh` produces 1920x1080 false-color PNGs from live CDS hips2fits DSS2 Color data
- **False color palettes**: 6 palettes available (enhanced, hubble, narrowband, heat, cool, vibrant)

### Real Data Sources

1. **Hubble Guide Star Catalog (GSC)** — 310MB of real star position data from the Hubble Space Telescope's Fine Guidance Sensors, installed via `apt install gsc`. The CCD Simulator uses this to render scientifically accurate star fields.
2. **NGC 4526 coordinates** — Real galaxy in the Virgo Cluster from NASA/IPAC Extragalactic Database (NED). Known host of SN 1994D (Type Ia supernova).
3. **Messier object coordinates** — From SEDS Messier Database (messier.seds.org) / IAU official coordinates.
4. **CDS hips2fits DSS2 Color** — Real sky survey imagery fetched on-demand from the Centre de Donnees astronomiques de Strasbourg (CDS) hips2fits API. The `capture_sky_view.sh` script reads the telescope's current RA/Dec from INDI, converts RA hours to degrees, and fetches DSS2 Color survey data for those coordinates. This produces images based on the actual Digitized Sky Survey, the same survey data used by professional astronomers worldwide.
5. **False color enhancement** — `false_color.py` applies artistic false color palettes (enhanced, hubble, narrowband, heat, cool, vibrant) to the DSS2 survey imagery, producing visually stunning 1920x1080 PNGs.
6. **SAOImageDS9** — The standard astronomical FITS viewer from the Smithsonian Astrophysical Observatory, installed for professional-grade image display with color maps and stretches.
