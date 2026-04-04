#!/bin/bash
# Setup script for Coordinate Plane Activity
set -e

echo "=== Setting up Coordinate Plane Activity ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure target directory exists and is owned by ga
mkdir -p /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Documents/Flipcharts

# Remove any pre-existing target files to ensure a clean start
TARGET_FILE="/home/ga/Documents/Flipcharts/coordinate_plane.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/coordinate_plane.flp"

rm -f "$TARGET_FILE" "$TARGET_FILE_ALT" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure ActivInspire is running
ensure_activinspire_running

# Focus ActivInspire window
focus_activinspire

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="
echo "Target File: $TARGET_FILE"
echo "Ready for agent."