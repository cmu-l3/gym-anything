#!/bin/bash
echo "=== Setting up kinematic_chain_build task ==="

source /workspace/scripts/task_utils.sh

# Create workspace directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/kinematic_sweep.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/kinematic_model.json 2>/dev/null || true

# STEP 2: Record timestamp
date +%s > /tmp/kinematic_chain_build_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
echo "Launching CoppeliaSim empty scene..."
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/kinematic_chain_build_start_screenshot.png

echo "=== Setup Complete ==="
echo "Empty CoppeliaSim scene loaded. Agent must programmatically build the 3-DOF arm and export FK validation data."