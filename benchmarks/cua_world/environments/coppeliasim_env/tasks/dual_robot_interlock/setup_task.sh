#!/bin/bash
echo "=== Setting up dual_robot_interlock task ==="

source /workspace/scripts/task_utils.sh

# Create workspace and export directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/interlock_telemetry.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/interlock_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/dual_robot_interlock_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent is required to load the robots and set up the scene programmatically or via GUI
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot as evidence
sleep 2
take_screenshot /tmp/dual_robot_interlock_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must load two UR5 robots, program the interlock, and export telemetry."