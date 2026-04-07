#!/bin/bash
echo "=== Setting up stack_stability_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/stack_stability_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/stack_stability_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/stack_stability_analysis_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# This tests the agent's ability to use the API to create objects and run simulations from scratch
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/stack_stability_analysis_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to perform stack stability analysis and export results."