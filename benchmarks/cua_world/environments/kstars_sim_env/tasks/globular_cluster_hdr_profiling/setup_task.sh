#!/bin/bash
set -e
echo "=== Setting up globular_cluster_hdr_profiling task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/M15_HDR
rm -f /home/ga/Documents/hdr_observation_plan.txt
rm -f /home/ga/Documents/hdr_summary.txt
rm -f /tmp/task_result.json

# 3. Create root directory (agent must create the time-specific subdirectories)
mkdir -p /home/ga/Images/M15_HDR
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/M15_HDR
chown -R ga:ga /home/ga/Documents

# 4. Start INDI and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure filter wheel
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 6. Unpark and slew to WRONG position (M3 - another globular cluster)
unpark_telescope
sleep 1
echo "Slewing telescope to initial decoy position (M3)..."
slew_to_coordinates 13.703 28.377
wait_for_slew_complete 20
echo "Telescope currently at M3. Agent must slew to M15."

# 7. Reset CCD to defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 8. Create the observation plan document
cat > /home/ga/Documents/hdr_observation_plan.txt << 'EOF'
GLOBULAR CLUSTER HDR PROFILING OBSERVATION PLAN
===============================================
Target: M15 (NGC 7078)
Right Ascension: 21h 29m 58s
Declination: +12d 10m 01s (J2000)

SCIENTIFIC OBJECTIVE
--------------------
M15 is a core-collapsed globular cluster. To accurately measure its radial
density profile from the dense core to the faint halo, a High Dynamic Range
(HDR) exposure sequence is required.

OBSERVING SEQUENCE
------------------
Filter: Luminance (Slot 1)
Frame Type: LIGHT

Execute the following exposures and save them into their respective subdirectories
inside the base directory: /home/ga/Images/M15_HDR/

1. 1-second exposures (Count: 5)
   -> Upload Directory: /home/ga/Images/M15_HDR/1s/

2. 5-second exposures (Count: 5)
   -> Upload Directory: /home/ga/Images/M15_HDR/5s/

3. 15-second exposures (Count: 5)
   -> Upload Directory: /home/ga/Images/M15_HDR/15s/

4. 60-second exposures (Count: 5)
   -> Upload Directory: /home/ga/Images/M15_HDR/60s/

*Note: You must create the subdirectories (1s, 5s, 15s, 60s) before capturing.*

SKY SURVEY CAPTURE
------------------
Produce a false-color representation of the field using the 'cool' palette
(simulates X-ray/UV characteristics of dense populations).
Run: bash ~/capture_sky_view.sh /home/ga/Images/M15_HDR/sky_view_cool.png 1.0 --palette cool

SUMMARY REPORT
--------------
Write an observation summary to: /home/ga/Documents/hdr_summary.txt
Include:
- Target Name (M15)
- Filter Used
- Confirmation that all 4 exposure brackets were completed
EOF

chown ga:ga /home/ga/Documents/hdr_observation_plan.txt

# 9. Ensure KStars is running and clear dialogs
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 10. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Observation plan at ~/Documents/hdr_observation_plan.txt"