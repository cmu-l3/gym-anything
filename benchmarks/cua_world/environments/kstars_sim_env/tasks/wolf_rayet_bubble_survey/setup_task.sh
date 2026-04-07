#!/bin/bash
set -e
echo "=== Setting up wolf_rayet_bubble_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -rf /home/ga/Images/WR_survey
rm -f /home/ga/Documents/wr_target_list.txt
rm -f /home/ga/Documents/wr_survey_report.md
rm -f /tmp/task_result.json

# 2. Create base directories
mkdir -p /home/ga/Images/WR_survey/WR_136/Ha
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/WR_survey
chown -R ga:ga /home/ga/Documents

# 3. ERROR INJECTION: Seed stale FITS files from a "previous" session
# These are touched with a 2024 timestamp so they predate the task execution.
# The agent must NOT confuse these with new captures.
touch -t 202401010000 /home/ga/Images/WR_survey/WR_136/Ha/old_ha_001.fits
touch -t 202401010000 /home/ga/Images/WR_survey/WR_136/Ha/old_ha_002.fits
chown ga:ga /home/ga/Images/WR_survey/WR_136/Ha/*.fits

# 4. Record task start time (anti-gaming, MUST happen after stale files are touched)
sleep 1
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Ensure INDI server is running with all simulators
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel with narrowband slots
# Agent must map Ha to slot 5 and OIII to slot 6 via the UI
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=SII" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# 7. Unpark telescope and slew to a neutral position (Polaris)
unpark_telescope
sleep 1
slew_to_coordinates 2.53 89.26
wait_for_slew_complete 20
echo "Telescope parked near NCP. Agent must slew to targets."

# 8. Reset CCD upload to a neutral location
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the observing plan document
cat > /home/ga/Documents/wr_target_list.txt << 'EOF'
WOLF-RAYET WIND-BLOWN BUBBLE SURVEY
====================================
Prepared by: Extragalactic & Stellar Astrophysics Group
Program ID: WR-NARROW-2025

SCIENTIFIC OBJECTIVE
--------------------
Execute a narrowband survey of three Galactic Wolf-Rayet stars to map their 
circumstellar wind-blown bubbles. 

TARGETS
-------
1. WR 136 (Crescent Nebula exciter)
   RA:  20h 12m 06s
   Dec: +38d 21m 18s (J2000)

2. WR 7 (Thor's Helmet exciter)
   RA:  06h 54m 13s
   Dec: -23d 55m 42s (J2000)

3. WR 134 (Ring Nebula in Cygnus)
   RA:  20h 10m 14s
   Dec: +35d 10m 46s (J2000)

OBSERVATIONAL PROTOCOL
----------------------
For EACH of the three targets, you must:
1. Slew the telescope to the target coordinates.
2. Ensure files are saved in the correct target/filter subdirectory tree:
   /home/ga/Images/WR_survey/<TARGET>/<FILTER>/
   (e.g., /home/ga/Images/WR_survey/WR_136/Ha/)
3. Capture at least two 60-second LIGHT frames using the Ha filter (Slot 5).
4. Capture at least two 60-second LIGHT frames using the OIII filter (Slot 6).
5. Generate a false-color sky survey visualization of the field:
   Run: bash ~/capture_sky_view.sh /home/ga/Images/WR_survey/<TARGET>/sky_<TARGET>.png 0.5 --palette cool

NOTE: There may be stale data in the WR_136 directory from an aborted run in 
2024. Ignore it and capture fresh exposures.

DELIVERABLE
-----------
Write a summary report to /home/ga/Documents/wr_survey_report.md
Include the names of the 3 targets observed and note any issues.
EOF

chown ga:ga /home/ga/Documents/wr_target_list.txt
echo "Observing plan written to /home/ga/Documents/wr_target_list.txt"

# 10. Ensure KStars is running and maximized
ensure_kstars_running
sleep 3
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="