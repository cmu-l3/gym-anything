#!/bin/bash
echo "=== Setting up soil_sampling_loiter_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the CSV data file containing the sampling coordinates
cat > /home/ga/Documents/QGC/sampling_points.csv << 'CSVEOF'
point_id,latitude,longitude,description
SP-01,47.39720,8.54350,Southwest corner - clay deposit
SP-02,47.39780,8.54350,West edge - transition zone
SP-03,47.39840,8.54350,Northwest corner - sandy loam
SP-04,47.39840,8.54550,Northeast corner - organic rich
SP-05,47.39780,8.54550,East edge - gravel substrate
SP-06,47.39720,8.54550,Southeast corner - alluvial soil
CSVEOF

chown ga:ga /home/ga/Documents/QGC/sampling_points.csv

# 3. Remove any pre-existing plan files to prevent false positives
rm -f /home/ga/Documents/QGC/soil_sampling.plan

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# 5. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== soil_sampling_loiter_mission task setup complete ==="
echo "Coordinates CSV: /home/ga/Documents/QGC/sampling_points.csv"
echo "Expected output: /home/ga/Documents/QGC/soil_sampling.plan"