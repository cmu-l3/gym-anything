#!/bin/bash
echo "=== Setting up mobile_path_tracking task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/path_tracking.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/path_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/mobile_path_tracking_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# The agent must programmatically load a mobile robot model and execute the navigation.
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/mobile_path_tracking_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must load a mobile robot, navigate waypoints, and export tracking results."