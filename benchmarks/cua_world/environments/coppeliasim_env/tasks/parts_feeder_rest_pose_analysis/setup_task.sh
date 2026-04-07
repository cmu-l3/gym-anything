#!/bin/bash
echo "=== Setting up parts_feeder_rest_pose_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
mkdir -p /home/ga/Documents/CoppeliaSim/scripts
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove any pre-existing output files (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/scripts/run_drop_test.py 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/drop_results.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/rest_pose_stats.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_ts

# Launch CoppeliaSim with default empty scene (agent must build scene)
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must create the scene, write the drop test script, and export the results."