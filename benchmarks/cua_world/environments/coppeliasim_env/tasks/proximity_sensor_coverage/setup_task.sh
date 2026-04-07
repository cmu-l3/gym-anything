#!/bin/bash
echo "=== Setting up proximity_sensor_coverage task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output BEFORE timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/sensor_coverage.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/sensor_analysis.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/proximity_sensor_coverage_start_ts

# STEP 3: Launch CoppeliaSim with empty scene (agent must build sensor scene from scratch)
# This tests the agent's ability to use the API to create objects and sensors programmatically
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/proximity_sensor_coverage_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with empty scene."
echo "Agent must programmatically create sensors, run coverage tests, and export results."
