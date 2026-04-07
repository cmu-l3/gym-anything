#!/bin/bash
echo "=== Setting up AGV Kinematic Swept Path Analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove any pre-existing output files (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/swept_corners.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/swept_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/agv_swept_path_start_ts

# Launch CoppeliaSim with an empty scene
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/agv_swept_path_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to programmatically animate the AGV and record swept path metrics."