#!/bin/bash
echo "=== Setting up gravity_torque_map task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/torque_map.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/torque_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/gravity_torque_map_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
launch_coppeliasim

# Focus and maximize window for VLM screenshot capturing
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot to prove empty starting state
sleep 2
take_screenshot /tmp/gravity_torque_map_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to load a robot, perform torque mapping, and export results."