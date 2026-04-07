#!/bin/bash
set -e
echo "=== Setting up veil_mosaic_survey task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/veil_mosaic
rm -f /home/ga/Documents/mosaic_plan.txt
rm -f /home/ga/Documents/mosaic_log.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/veil_mosaic/panel_1
mkdir -p /home/ga/Images/veil_mosaic/panel_2
mkdir -p /home/ga/Images/veil_mosaic/panel_3
mkdir -p /home/ga/Images/veil_mosaic/panel_4
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/veil_mosaic
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI and connect devices ─────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel (Agent must find H-alpha is slot 5) ─────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=SII" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# ── 6. Unpark telescope and slew to WRONG position ────────────────────
unpark_telescope
sleep 1
# Point at M45 (Pleiades) - completely wrong target area
slew_to_coordinates 3.7867 24.117
wait_for_slew_complete 20
echo "Telescope at M45 (wrong position). Agent must compute coordinates and slew to Veil Nebula."

# ── 7. Configure CCD upload defaults ──────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the mosaic planning document ────────────────────────────
cat > /home/ga/Documents/mosaic_plan.txt << 'EOF'
MOSAIC IMAGING PLAN — NGC 6992 (Eastern Veil Nebula)
=====================================================
PI: Dr. Sarah Chen, Cygnus Loop SNR Emission Survey
Season: Current
Priority: HIGH — clear skies window, complete before meridian transit

SCIENTIFIC OBJECTIVE:
Acquire a 2×2 H-alpha mosaic of the Eastern Veil Nebula (NGC 6992/6995)
filamentary region. These data will be combined with existing OIII and SII
mosaics to produce a three-color emission map of the shock front.

TARGET:
  Object:  NGC 6992 (Eastern Veil Nebula)
  Type:    Supernova remnant filament
  Central coordinates:  RA 20h 56m 24s,  Dec +31° 43' 00"

CCD CONFIGURATION:
  Telescope focal length: 750mm
  Filter: H-alpha — FILTER WHEEL SLOT 5
  Frame type: LIGHT
  Exposure time: 45 seconds per frame
  Frames per panel: 3

MOSAIC GRID LAYOUT:
  Grid dimensions: 2 columns × 2 rows (4 panels total)
  Overlap between adjacent panels: 10%
  Effective panel step in RA direction: 0.46° (divide by cos(Dec) for RA hours)
  Effective panel step in Dec direction: 0.37°

  Sky orientation (North up, East left):

      Panel 1 (NW)  |  Panel 2 (NE)
    -----------------+-----------------
      Panel 3 (SW)  |  Panel 4 (SE)

  To compute panel centers, offset from the mosaic center by ±half the
  panel step in each axis. Remember: RA offsets must be divided by
  cos(Declination) when converting from degrees to hours.

DATA MANAGEMENT:
  Base directory:  /home/ga/Images/veil_mosaic/
  Panel 1 upload:  /home/ga/Images/veil_mosaic/panel_1/
  Panel 2 upload:  /home/ga/Images/veil_mosaic/panel_2/
  Panel 3 upload:  /home/ga/Images/veil_mosaic/panel_3/
  Panel 4 upload:  /home/ga/Images/veil_mosaic/panel_4/

  IMPORTANT: Set the CCD upload directory to the correct panel_N path
  BEFORE beginning exposures for that panel.

DELIVERABLES:
  1. All FITS frames organized in the per-panel subdirectories listed above
  2. Mosaic observation log at: /home/ga/Documents/mosaic_log.txt
     For each panel, record: panel number, RA (hours), Dec (degrees),
     number of frames captured, and exposure time
  3. One sky capture at any panel position:
     bash ~/capture_sky_view.sh ~/Images/veil_mosaic/sky_preview.png

NOTES:
  - Keep H-alpha filter (slot 5) selected for ALL panels
  - If in doubt about coordinate calculation, the panel centers should
    be separated by ~0.46° in Dec and ~0.46°/cos(31.7°) in RA
EOF

chown ga:ga /home/ga/Documents/mosaic_plan.txt
echo "Mosaic plan written to /home/ga/Documents/mosaic_plan.txt"

# ── 9. Ensure KStars is running and maximized ─────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 10. Record initial FITS count & Take Initial Screenshot ───────────
INITIAL_FITS=$(find /home/ga/Images/veil_mosaic 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="