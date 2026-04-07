#!/bin/bash
echo "=== Setting up robot_depth_scanning_reconstruction task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/merged_pointcloud.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/scanning_report.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/depth_view_*.csv 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/robot_depth_scanning_start_ts

# STEP 3: Launch CoppeliaSim with the multi-arm scene so robot is available
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene not found, launching empty scene"
    launch_coppeliasim
fi

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/robot_depth_scanning_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with robot arm scene."
echo "Agent must use ZMQ Remote API to mount a depth sensor, scan an object, and reconstruct a 3D point cloud."