#!/bin/bash
echo "=== Setting up evaluate_road_diet_lane_reduction task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean the output directory to ensure a clean starting state
rm -rf /home/ga/SUMO_Output/*
mkdir -p /home/ga/SUMO_Output
chown ga:ga /home/ga/SUMO_Output

# Make sure no SUMO processes are lingering
kill_sumo

# Take initial screenshot of the terminal
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="