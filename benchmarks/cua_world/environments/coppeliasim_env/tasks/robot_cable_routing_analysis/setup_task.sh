#!/bin/bash
echo "=== Setting up robot_cable_routing_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/cable_measurements.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/cable_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/robot_cable_routing_analysis_start_ts

# STEP 3: Launch CoppeliaSim with an appropriate scene (movementViaRemoteApi.ttt has a ready 6-DOF arm)
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Target scene not found, launching empty scene"
    launch_coppeliasim
fi

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/robot_cable_routing_analysis_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must instrument the robot with cable ties and calculate lengths."