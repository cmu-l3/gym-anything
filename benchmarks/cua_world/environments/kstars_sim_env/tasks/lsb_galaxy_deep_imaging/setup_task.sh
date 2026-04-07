#!/bin/bash
set -e
echo "=== Setting up lsb_galaxy_deep_imaging task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/lsb
rm -f /home/ga/Documents/lsb_imaging_plan.txt
rm -f /home/ga/Documents/malin1_report.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/lsb/malin1
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/lsb
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed aborted trap frames from ambient session ──
# These must NOT count toward the required frames
touch -t 202401010000 /home/ga/Images/lsb/malin1/aborted_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/lsb/malin1/aborted_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/lsb/malin1/aborted_003.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/lsb/malin1

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
sleep 1

# ── 7. Reset CCD to defaults (ambient temp, 1x1 binning) ───────────────
# Explicitly set the simulator to an unoptimized state for deep imaging
indi_setprop "CCD Simulator.CCD_BINNING.HOR_BIN=1;VER_BIN=1" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_TEMPERATURE.CCD_TEMPERATURE_VALUE=10" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_COOLER.COOLER_OFF=On" 2>/dev/null || true
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Unpark and slew to neutral position (NCP) ───────────────────────
unpark_telescope
sleep 1
slew_to_coordinates 0.0 89.0
wait_for_slew_complete 15
echo "Telescope at NCP. Agent must find Malin 1."

# ── 9. Create the imaging plan document ───────────────────────────────
cat > /home/ga/Documents/lsb_imaging_plan.txt << 'EOF'
DEEP IMAGING QUEUE — LOW SURFACE BRIGHTNESS (LSB) TARGET
=========================================================
Project: Giant LSB Spiral Morphologies

TARGET
------
Name: Malin 1
Type: Giant Low Surface Brightness Spiral Galaxy
Right Ascension: 12h 36m 59.3s
Declination:     +13d 59m 54s (J2000)
Constellation: Coma Berenices

HARDWARE REQUIREMENTS (CRITICAL)
--------------------------------
Malin 1 is extraordinarily faint. The galactic disk is darker than the
background night sky glow. To achieve adequate SNR, you MUST manipulate
the camera hardware state before starting the capture sequence:

1. ACTIVE COOLING: Enable the CCD cooler and set the target 
   temperature to exactly -20°C to suppress dark current noise.
2. SENSOR BINNING: Configure the CCD for 2x2 hardware binning 
   (Horizontal=2, Vertical=2) to maximize per-pixel photon collection.
3. FILTER: Use the Luminance filter (slot 1) for maximum throughput.

EXPOSURE PLAN
-------------
Upload Directory: /home/ga/Images/lsb/malin1/
Exposure Time: 300 seconds
Number of Frames: >= 4 LIGHT frames

POST-OBSERVATION TASKS
----------------------
1. Sky Context: Generate a false-color sky map of the field using the
   'cool' palette to highlight extended blue structures:
   bash ~/capture_sky_view.sh /home/ga/Images/lsb/malin1/malin1_sky.png 0.5 --palette cool

2. Session Report: Create a summary report at 
   ~/Documents/malin1_report.txt
   Please state the target name, number of frames captured, and confirm 
   that the -20C cooling and 2x2 binning were successfully applied.

NOTE: There may be pre-existing aborted frames in the upload directory 
from an earlier ambient-temperature test. Please ignore them and just 
capture your new 300s deep integration frames.
EOF

chown ga:ga /home/ga/Documents/lsb_imaging_plan.txt

# ── 10. Ensure KStars is running ───────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial state ───────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Malin 1"
echo "Requires: CCD Cooling (-20C) and 2x2 Binning"