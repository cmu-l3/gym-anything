#!/bin/bash
echo "=== Setting up payload_torque_validation task ==="

source /workspace/scripts/task_utils.sh

# Ensure export directory exists and permissions are correct
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files (anti-gaming baseline)
rm -f /home/ga/Documents/CoppeliaSim/exports/payload_torque_curve.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/payload_capacity_report.json 2>/dev/null || true

# Record task start timestamp for anti-gaming file freshness checks
date +%s > /tmp/payload_torque_validation_start_ts

# Launch CoppeliaSim with an empty scene
# (Agent must load the robot and construct the payload scene via API)
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot to document starting state
sleep 2
take_screenshot /tmp/payload_torque_validation_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with an empty scene."
echo "Agent must load the UR5 model, attach payload, run physics tests, and export results."