#!/bin/bash
set -e
echo "=== Setting up lsb_galaxy_deep_survey task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/LSB_survey
rm -f /home/ga/Documents/lsb_targets.txt
rm -f /home/ga/Documents/lsb_survey_report.txt
rm -f /tmp/task_result.json

# ── 2. Create base directory structure ────────────────────────────────
mkdir -p /home/ga/Images/LSB_survey/targets
mkdir -p /home/ga/Images/LSB_survey/calibration/darks_25s
mkdir -p /home/ga/Documents

# ── 3. ERROR INJECTION: Seed 3 stale dark frames ─────────────────────
# These predate the session and must NOT be counted by the verifier
touch -t 202401010000 /home/ga/Images/LSB_survey/calibration/darks_25s/stale_dark_001.fits
touch -t 202401010000 /home/ga/Images/LSB_survey/calibration/darks_25s/stale_dark_002.fits
touch -t 202401010000 /home/ga/Images/LSB_survey/calibration/darks_25s/stale_dark_003.fits

chown -R ga:ga /home/ga/Images/LSB_survey
chown -R ga:ga /home/ga/Documents

# ── 4. Record task start time (anti-gaming, must be after stale files) 
sleep 1
date +%s > /tmp/task_start_time.txt

# ── 5. Create the target list document ────────────────────────────────
cat > /home/ga/Documents/lsb_targets.txt << 'EOF'
LOW SURFACE BRIGHTNESS (LSB) GALAXY SURVEY TARGETS
==================================================
Project ID: LSB-DEEP-09
PI: Extragalactic Research Group

TARGET 1
Name: Malin 1
RA: 12h 36m 59s
Dec: +14d 19m 49s (J2000)

TARGET 2
Name: Malin 2
RA: 10h 39m 52s
Dec: +20d 50m 49s (J2000)

TARGET 3
Name: UGC 1382
RA: 01h 54m 41s
Dec: -00d 08m 36s (J2000)

INSTRUCTIONS
------------
For EACH target:
1. Slew to coordinates.
2. Set upload directory to: /home/ga/Images/LSB_survey/targets/<Target_Name>/
   (e.g., Malin_1, Malin_2, UGC_1382)
3. Frame Type: LIGHT. Exposure: 25 seconds.
4. Capture exactly 4 frames.
5. Capture deep sky field using the cool palette:
   bash ~/capture_sky_view.sh /home/ga/Images/LSB_survey/targets/<Target_Name>/view.png --palette cool

CALIBRATION (Do this LAST)
--------------------------
1. Set upload directory to: /home/ga/Images/LSB_survey/calibration/darks_25s/
2. Frame Type: DARK
3. Exposure: 25 seconds
4. Capture exactly 5 frames.

(Note: Do not count any old stale frames that might be in the folder from previous aborted runs)

REPORT
------
Write a report confirming observations to: ~/Documents/lsb_survey_report.txt
Make sure to list the three observed targets by name.
EOF

chown ga:ga /home/ga/Documents/lsb_targets.txt

# ── 6. Start INDI and connect devices ─────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 7. Unpark telescope and slew to WRONG decoy position ──────────────
unpark_telescope
sleep 1
# Slew to UGC 6614 (a different LSB galaxy not in the survey)
slew_to_coordinates 11.654 17.143
wait_for_slew_complete 20

# ── 8. Reset CCD defaults ─────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=1" 2>/dev/null || true

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

# ── 10. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target list at ~/Documents/lsb_targets.txt"