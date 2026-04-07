#!/bin/bash
set -e
echo "=== Setting up bok_globule_extinction_mapping task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/dark_nebulae
rm -f /home/ga/Documents/observation_manifest.txt
rm -f /home/ga/Documents/extinction_survey_log.csv
rm -f /tmp/task_result.json

# 3. Create root output directory and inject decoy
mkdir -p /home/ga/Images/dark_nebulae/B68/B
mkdir -p /home/ga/Documents

# INJECT DECOY: Create a stale bias/test frame from a "previous session"
# This file has a timestamp from 2023 and should NOT be counted by the verifier
touch -t 202301010000 /home/ga/Images/dark_nebulae/B68/B/decoy_frame.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/dark_nebulae
chown -R ga:ga /home/ga/Documents

# 4. Start INDI server and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure Filter Wheel
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 6. Set Focuser to baseline position
indi_setprop "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION=30000" 2>/dev/null || true

# 7. Unpark telescope and slew to WRONG position
unpark_telescope
sleep 1
# Point at North Galactic Pole (Coma Berenices) - far from the Sagittarius/Ophiuchus targets
slew_to_coordinates 12.85 27.11
wait_for_slew_complete 20
echo "Telescope at Coma Berenices. Agent must discover and slew to Bok globules."

# 8. Reset CCD upload
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create observation manifest
cat > /home/ga/Documents/observation_manifest.txt << 'EOF'
BOK GLOBULE EXTINCTION SURVEY - TARGET MANIFEST
===============================================
PI: ISM Research Group
Goal: Multi-band optical imaging of dark nebulae to measure dust extinction (E(B-V) and Av).

TARGETS
-------
1. Barnard 68 (B68)
   RA: 17h 22m 38s (17.3772)
   Dec: -23d 49m 34s (-23.8261)

2. Barnard 72 (B72 - Snake Nebula)
   RA: 17h 23m 30s (17.3916)
   Dec: -23d 38m 00s (-23.6333)

3. Barnard 86 (B86 - Ink Spot)
   RA: 18h 03m 00s (18.0500)
   Dec: -27d 52m 00s (-27.8666)

OBSERVATION PROTOCOL
--------------------
For EACH of the three targets above, you must execute the following sequence:

1. Create target and filter subdirectories:
   /home/ga/Images/dark_nebulae/<target_name>/<filter_name>/
   (e.g., /home/ga/Images/dark_nebulae/B68/B/)

2. Apply Chromatic Aberration Focus Offsets & Image:
   The telescope has longitudinal chromatic aberration. You MUST manually adjust the
   Focuser Simulator absolute position for each filter before taking the exposures.
   
   Filter B (Slot 3):
     - Set Focuser absolute position to: 30100
     - Set CCD upload directory to target's B/ folder
     - Take >= 2 exposures of 60 seconds (LIGHT)
     
   Filter V (Slot 2):
     - Set Focuser absolute position to: 30000
     - Set CCD upload directory to target's V/ folder
     - Take >= 2 exposures of 60 seconds (LIGHT)
     
   Filter R (Slot 4):
     - Set Focuser absolute position to: 29900
     - Set CCD upload directory to target's R/ folder
     - Take >= 2 exposures of 60 seconds (LIGHT)

3. Capture Sky Survey Reference:
   Run the capture script to download the DSS2 optical survey image of the cloud.
   bash ~/capture_sky_view.sh /home/ga/Images/dark_nebulae/<target_name>/sky_view.png 0.5 --palette enhanced

DELIVERABLES
------------
1. FITS files properly sorted into the directory tree with correct focus applied.
2. The 3 sky_view.png survey reference images.
3. A summary CSV log saved to: /home/ga/Documents/extinction_survey_log.csv
   Format exactly with these headers:
   Target,RA,Dec,Total_Frames
   B68,17.3772,-23.8261,6
   (Add rows for all three targets, with the total frames you successfully captured for each)
EOF

chown ga:ga /home/ga/Documents/observation_manifest.txt
echo "Manifest written to /home/ga/Documents/observation_manifest.txt"

# 10. Ensure KStars is running
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="