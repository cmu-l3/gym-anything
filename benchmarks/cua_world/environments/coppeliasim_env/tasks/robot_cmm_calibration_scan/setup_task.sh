#!/bin/bash
echo "=== Setting up robot_cmm_calibration_scan task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/scan_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/calibration_metrics.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/calibration_setup.ttt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/robot_cmm_calibration_scan_start_ts

# Launch with movementViaRemoteApi.ttt (IK scene preferred for this task)
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Target scene not found, launching empty scene"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot to capture original UI/environment state
sleep 2
take_screenshot /tmp/robot_cmm_calibration_scan_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must construct the gauge block, attach sensor, scan, and save results."