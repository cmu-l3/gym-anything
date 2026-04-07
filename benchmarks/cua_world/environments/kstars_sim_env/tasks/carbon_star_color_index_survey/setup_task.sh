#!/bin/bash
set -e
echo "=== Setting up carbon_star_color_index_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/carbon_lab
rm -f /home/ga/Documents/lab_prep_request.txt
rm -f /home/ga/Documents/lab_summary.csv
rm -f /tmp/task_result.json

# 3. Create root dir and stale data directory
mkdir -p /home/ga/Images/carbon_lab/U_Hydrae
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/carbon_lab
chown -R ga:ga /home/ga/Documents

# 4. ERROR INJECTION: Stale data from previous semester
# Pre-date these files so they do not count toward completion
touch -t 202401010000 /home/ga/Images/carbon_lab/U_Hydrae/old_B_frame.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/carbon_lab/U_Hydrae/old_R_frame.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/carbon_lab/U_Hydrae/sky_view.png 2>/dev/null || true
chown -R ga:ga /home/ga/Images/carbon_lab/U_Hydrae

# 5. Start INDI server and connect simulators
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 7. Unpark telescope and slew to Spica (wrong position, blue star)
unpark_telescope
sleep 1
slew_to_coordinates 13.419 -11.161
wait_for_slew_complete 20
echo "Telescope at Spica."

# 8. Set CCD upload defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the lab prep request document
cat > /home/ga/Documents/lab_prep_request.txt << 'EOF'
ASTROPHYSICS LAB PREPARATION REQUEST
====================================
Course: ASTRO 301 - Stellar Evolution
Topic: AGB Stars and Carbon Star Color Indices

We need to prepare a dataset demonstrating the extreme B-R color index of carbon stars.
Please observe the following 4 famous carbon stars.

TARGETS:
1. R_Leporis (Hind's Crimson Star)
   RA: 04h 59m 36s, Dec: -14d 48m 22s
2. T_Lyrae
   RA: 18h 32m 20s, Dec: +36d 59m 56s
3. V_Aquilae
   RA: 19h 04m 24s, Dec: -05d 41m 05s
4. W_Orionis
   RA: 05h 05m 24s, Dec: +01d 10m 40s

REQUIREMENTS PER TARGET:
- Create a subdirectory for each target: ~/Images/carbon_lab/<Target_Name>/
- Change the CCD upload directory to the target's subdirectory before taking exposures.
- Take one B-band exposure (slot 3). Exposure time = 45s.
- Take one R-band exposure (slot 4). Exposure time = 45s.
- Generate a vibrant sky view capture in the same subdirectory named "sky_view.png".
  Command: bash ~/capture_sky_view.sh ~/Images/carbon_lab/<Target_Name>/sky_view.png 1.0 --palette vibrant

SUMMARY REPORT:
Compile a CSV summary report at ~/Documents/lab_summary.csv
Format:
Target, RA, Dec, B_frames, R_frames, Sky_Capture_Exists
(List the 4 targets above. Do NOT include U_Hydrae from last semester.)

NOTE:
A subdirectory for U_Hydrae already exists from last semester. Please ignore it. All files you generate must be new.
EOF
chown ga:ga /home/ga/Documents/lab_prep_request.txt

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

# 11. Record initial state screenshot
take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="