#!/bin/bash
echo "=== Setting up payload_com_identification task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/ft_measurements.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/payload_identification.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/payload_com_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene.
# The agent must construct the physical test rig from primitives.
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/payload_com_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must construct the F/T sensor rig, step simulation, record forces, and mathematically extract payload properties."