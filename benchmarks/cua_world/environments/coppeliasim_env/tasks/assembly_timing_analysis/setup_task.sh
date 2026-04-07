#!/bin/bash
echo "=== Setting up assembly_timing_analysis task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output BEFORE timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/cycle_timing.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/timing_report.json 2>/dev/null || true

# STEP 2: Record timestamp
date +%s > /tmp/assembly_timing_analysis_start_ts

# STEP 3: Launch with pick-and-place demo scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "pickAndPlaceDemo.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "pickAndPlaceDemo.ttt not found, launching empty"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/assembly_timing_analysis_start_screenshot.png

echo "=== Setup Complete ==="
echo "Pick-and-place scene loaded. Agent must run simulation, measure cycles, and export timing data."
