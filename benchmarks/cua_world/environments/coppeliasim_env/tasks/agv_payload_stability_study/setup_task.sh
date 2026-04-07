#!/bin/bash
echo "=== Setting up agv_payload_stability_study task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/stability_trials.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/stability_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/agv_payload_stability_study_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# The agent is expected to use the ZMQ Remote API to programmatically build the platform and payload
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/agv_payload_stability_study_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must programmatically construct the payload/platform, run trials, and export results."