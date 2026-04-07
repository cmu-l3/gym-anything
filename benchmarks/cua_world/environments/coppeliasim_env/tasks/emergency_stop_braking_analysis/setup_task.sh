#!/bin/bash
echo "=== Setting up emergency_stop_braking_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/braking_analysis.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/safety_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/braking_analysis_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene. 
# Agent is required to instantiate a robot dynamically to ensure a clean physics start.
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/braking_analysis_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to perform dynamic braking tests and export results."