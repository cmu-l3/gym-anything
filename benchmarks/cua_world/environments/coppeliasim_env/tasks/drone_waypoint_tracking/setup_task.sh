#!/bin/bash
echo "=== Setting up drone_waypoint_tracking task ==="

source /workspace/scripts/task_utils.sh

# Create workspace directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/flight_log.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/flight_metrics.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/drone_waypoint_tracking_start_ts

# Launch CoppeliaSim with an empty scene (agent must load the drone model programmatically)
launch_coppeliasim

# Focus and maximize window for visual tracking and VLM
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot showing clean state
sleep 2
take_screenshot /tmp/drone_waypoint_tracking_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with empty scene."
echo "Agent must load the quadcopter, command it through waypoints, and export flight data."