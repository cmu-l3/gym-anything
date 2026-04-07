#!/bin/bash
echo "=== Setting up rubble_traversability_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/traversability_timeseries.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/traversability_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/rubble_traversability_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/rubble_traversability_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must programmatically construct procedural rubble fields, spawn a robot, simulate traversal, and export telemetry."