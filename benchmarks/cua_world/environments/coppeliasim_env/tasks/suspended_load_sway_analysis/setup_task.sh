#!/bin/bash
echo "=== Setting up suspended_load_sway_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories and set permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/sway_timeseries.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/sway_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/suspended_load_sway_analysis_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# This ensures the agent must programmatically create the mechanism from scratch
launch_coppeliasim

# Focus and maximize the window for visibility
focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial state screenshot
sleep 2
take_screenshot /tmp/suspended_load_sway_analysis_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must build the crane via ZMQ Remote API, run the trials, and export data."