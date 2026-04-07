#!/bin/bash
echo "=== Setting up synthetic_vision_domain_randomization task ==="

source /workspace/scripts/task_utils.sh

# Prepare clean export directory
mkdir -p /home/ga/Documents/CoppeliaSim/exports
rm -rf /home/ga/Documents/CoppeliaSim/exports/dataset 2>/dev/null || true
mkdir -p /home/ga/Documents/CoppeliaSim/exports/dataset
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/synthetic_vision_start_ts

# Launch CoppeliaSim with an empty scene
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/synthetic_vision_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with empty scene."
echo "Agent must programmatically construct the scene and generate the domain randomized dataset."