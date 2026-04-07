#!/bin/bash
echo "=== Setting up camera_fov_coverage_optimization task ==="

source /workspace/scripts/task_utils.sh

# Create output directories with correct permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files before timestamping to prevent gaming
rm -f /home/ga/Documents/CoppeliaSim/exports/camera_coverage_sweep.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/optimal_camera_placement.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/coverage_script.py 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/optimized_scene.ttt 2>/dev/null || true

# Record task start timestamp for verification
date +%s > /tmp/camera_fov_coverage_start_ts

# Launch CoppeliaSim with an empty scene. The agent must build the scene and code programmatically.
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/camera_fov_coverage_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must create targets, a vision sensor, and write an optimization script."