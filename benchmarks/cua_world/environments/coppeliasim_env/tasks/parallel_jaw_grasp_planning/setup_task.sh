#!/bin/bash
echo "=== Setting up parallel_jaw_grasp_planning task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/grasp_evaluations.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/optimal_grasp.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/parallel_jaw_grasp_planning_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent is required to construct the scene (workpiece + sensors) programmatically
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot to verify empty starting state
sleep 2
take_screenshot /tmp/parallel_jaw_grasp_planning_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must build the workpiece/gripper, sweep poses, and export grasp results."