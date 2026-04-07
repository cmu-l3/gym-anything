#!/bin/bash
set -e
echo "=== Setting up ndt_surface_scan_path_generation task ==="

source /workspace/scripts/task_utils.sh

# Create output directories and fix permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Anti-gaming: Ensure output files do not exist before task starts
rm -f /home/ga/Documents/CoppeliaSim/exports/scan_path.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/scan_report.json 2>/dev/null || true

# Record task start timestamp for verification
date +%s > /tmp/task_start_time.txt

# Launch CoppeliaSim with an empty scene.
# The agent must programmatically construct the sphere and sensors.
launch_coppeliasim ""

# Ensure window is visible and focused
focus_coppeliasim
maximize_coppeliasim

# Let UI settle and dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial state screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with empty scene. Agent must use ZMQ API to build geometry and scan paths."