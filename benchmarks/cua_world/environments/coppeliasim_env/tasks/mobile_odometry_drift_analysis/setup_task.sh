#!/bin/bash
echo "=== Setting up mobile_odometry_drift_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/odometry_track.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/odometry_summary.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/odometry_drift_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene.
# Note: The agent is expected to use the API (e.g., sim.loadModel) to instantiate the Pioneer P3DX.
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/odometry_drift_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running."
echo "Agent must use ZMQ Remote API to perform odometry drift analysis and export results."