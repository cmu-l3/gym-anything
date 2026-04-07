#!/bin/bash
echo "=== Setting up gravity_chute_optimization task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files (anti-gaming check)
rm -f /home/ga/Documents/CoppeliaSim/exports/chute_kinematics.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/chute_optimization.json 2>/dev/null || true

# Record task start timestamp for verification
date +%s > /tmp/gravity_chute_start_ts

# Launch CoppeliaSim with an empty scene
# The agent is expected to programmatically create the chute and the part
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot to verify starting state
sleep 2
take_screenshot /tmp/gravity_chute_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with empty scene."
echo "Agent must programmatically construct the simulation and run the parameter sweep."