#!/bin/bash
echo "=== Setting up kinematic_swept_volume_voxelization task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/swept_voxels.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/volume_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/task_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene. 
# The agent is expected to load a robot model via the UI or API.
echo "Launching CoppeliaSim..."
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot to prove starting state
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must load a robot arm, sweep a trajectory, and export voxelized volume data."