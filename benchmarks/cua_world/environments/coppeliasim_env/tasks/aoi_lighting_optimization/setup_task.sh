#!/bin/bash
echo "=== Setting up aoi_lighting_optimization task ==="

source /workspace/scripts/task_utils.sh

# Create output directories with correct permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/lighting_sweep.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/lighting_report.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/optimal_inspection.png 2>/dev/null || true

# Record task start timestamp for file verification
date +%s > /tmp/aoi_lighting_optimization_start_ts

# Launch CoppeliaSim with an empty scene (agent must build everything from scratch)
launch_coppeliasim

# Bring the window to the foreground and maximize it
focus_coppeliasim
maximize_coppeliasim

# Wait for UI to settle and dismiss initial startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/aoi_lighting_optimization_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must use ZMQ Remote API to build the AOI scene, sweep the light, and export results."