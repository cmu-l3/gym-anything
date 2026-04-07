#!/bin/bash
echo "=== Setting up agv_incline_torque_sizing task ==="

source /workspace/scripts/task_utils.sh

# Create output directories and set permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/incline_profiling.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/motor_sizing_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/agv_incline_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent is required to load the AGV, build the ramp, and execute the tests via the API
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/agv_incline_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with an empty scene."
echo "Agent must programmatically load an AGV, build a ramp, run incline tests, and export results."