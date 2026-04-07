#!/bin/bash
set -euo pipefail

echo "=== Setting up friction_sensitivity_study task ==="

source /workspace/scripts/task_utils.sh

# Create output directories with proper permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files to prevent gaming
rm -f /home/ga/Documents/CoppeliaSim/exports/friction_sweep.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/friction_report.json 2>/dev/null || true

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Launch CoppeliaSim with an empty scene.
# This forces the agent to programmatically build the simulation environment via API.
echo "Launching CoppeliaSim with an empty scene..."
launch_coppeliasim

# Ensure the window is visible and ready
focus_coppeliasim
maximize_coppeliasim

# Give it a moment to stabilize, then dismiss any popups
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to build the test rig, sweep friction, and export results."