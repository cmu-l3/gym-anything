#!/bin/bash
echo "=== Setting up redundant_nullspace_exploration task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
mkdir -p /home/ga/Documents/CoppeliaSim/scripts
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/nullspace_configs.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/nullspace_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp for anti-gaming
date +%s > /tmp/nullspace_exploration_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent is required to instantiate the robot model and run scripts either via ZMQ or internal Lua/Python
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/nullspace_exploration_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim loaded with an empty scene."
echo "Agent must load a 7-DOF robot, compute null-space configurations, and export results."