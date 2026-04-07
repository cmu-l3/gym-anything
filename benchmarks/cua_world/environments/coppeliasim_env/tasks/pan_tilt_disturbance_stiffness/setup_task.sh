#!/bin/bash
echo "=== Setting up pan_tilt_disturbance_stiffness task ==="

source /workspace/scripts/task_utils.sh

# Create output directories with proper permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/disturbance_timeseries.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/stiffness_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp for verification
date +%s > /tmp/pan_tilt_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# The agent is required to construct the mechanism programmatically via the API
echo "Launching CoppeliaSim with an empty scene..."
launch_coppeliasim

# Ensure window is visible and ready
focus_coppeliasim
maximize_coppeliasim

# Give UI time to stabilize and clear any startup popups
sleep 3
dismiss_dialogs

# Take initial screenshot as proof of the starting state
sleep 1
take_screenshot /tmp/pan_tilt_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must build the pan-tilt mechanism, apply force disturbances, and export response data."