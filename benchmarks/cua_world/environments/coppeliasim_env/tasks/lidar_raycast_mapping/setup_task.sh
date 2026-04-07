#!/bin/bash
echo "=== Setting up lidar_raycast_mapping task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/lidar_point_cloud.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/mapping_report.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/mapping_arena.ttt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/lidar_raycast_mapping_start_ts

# Launch CoppeliaSim with an empty scene
# Agent is required to programmatically build the room and sensor from scratch
launch_coppeliasim

# Focus and maximize the window
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/lidar_raycast_mapping_start.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Waiting for agent to construct the environment and extract point cloud."