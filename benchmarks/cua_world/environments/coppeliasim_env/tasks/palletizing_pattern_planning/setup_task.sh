#!/bin/bash
echo "=== Setting up palletizing_pattern_planning task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/pallet_positions.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/pallet_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/palletizing_task_start_ts

# STEP 3: Launch CoppeliaSim with the multi-arm remote API scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene movementViaRemoteApi.ttt not found, launching empty scene"
    launch_coppeliasim
fi

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/palletizing_task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with robot arm scene."
echo "Agent must programmatically plan and execute a palletizing grid and export results."