#!/bin/bash
echo "=== Setting up rotary_unbalance_vibration_study task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output BEFORE timestamp to prevent gaming
rm -f /home/ga/Documents/CoppeliaSim/exports/vibration_sweep.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/resonance_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/rotary_unbalance_vibration_study_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent must construct the dynamic hierarchy programmatically
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/rotary_unbalance_vibration_study_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running with an empty scene."
echo "Agent must programmatically construct the mechanism, run the sweep, and export results."