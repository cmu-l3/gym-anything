#!/bin/bash
echo "=== Setting up dual_arm_collision_avoidance task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/trial_logs.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/coordination_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/dual_arm_collision_avoidance_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# The agent must programmatically instantiate the robots
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/dual_arm_collision_avoidance_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to instantiate robots, detect collisions, and export results."