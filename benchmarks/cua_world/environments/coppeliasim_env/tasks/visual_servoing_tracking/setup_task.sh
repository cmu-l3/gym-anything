#!/bin/bash
echo "=== Setting up visual_servoing_tracking task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports/frames
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/tracking_log.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/servoing_report.json 2>/dev/null || true
rm -rf /home/ga/Documents/CoppeliaSim/exports/frames/* 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/visual_servoing_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent must construct the sensor and target programmatically
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/visual_servoing_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with empty scene. ZMQ Remote API ready on port 23000."
echo "Agent must programmatically create vision sensor, animate target, process images with OpenCV, and actuate camera."