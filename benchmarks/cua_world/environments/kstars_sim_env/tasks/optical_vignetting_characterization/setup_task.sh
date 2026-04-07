#!/bin/bash
set -e
echo "=== Setting up optical_vignetting_characterization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any artifacts from previous runs
rm -rf /home/ga/Calibration
rm -f /home/ga/analyze_sensor.py
rm -f /home/ga/Documents/sensor_report.txt
rm -f /tmp/task_result.json

# Create root directories (agent must create Bias/Flats subdirectories)
mkdir -p /home/ga/Calibration
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Calibration
chown -R ga:ga /home/ga/Documents

# Ensure INDI server is running with all simulators
ensure_indi_running
sleep 2
connect_all_devices

# Configure filter wheel with Luminance in Slot 1
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
sleep 1

# Unpark telescope and move to a neutral position
unpark_telescope
sleep 1
slew_to_coordinates 12.0 45.0
echo "Telescope initialized."

# Set CCD to defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# Ensure KStars is running and maximized
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
echo "Filter 1 set to 'Luminance'."