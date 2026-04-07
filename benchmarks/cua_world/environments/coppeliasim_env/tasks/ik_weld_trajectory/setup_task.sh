#!/bin/bash
echo "=== Setting up ik_weld_trajectory task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/weld_trajectory.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/weld_stats.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/ik_weld_trajectory_start_ts

# STEP 3: Launch CoppeliaSim with the IK obstacle avoidance scene
# (has a robot arm with IK already configured — agent must discover and use it)
SCENE=$(find /opt/CoppeliaSim/scenes -name "obstacleAvoidanceAndIk.ttt" 2>/dev/null | head -1)
if [ -z "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "*smoothMovements*" -o -name "*ik*" 2>/dev/null | head -1)
fi
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading IK scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "IK scene not found, launching empty scene"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/ik_weld_trajectory_start_screenshot.png

echo "=== Setup Complete ==="
echo "IK scene loaded. Agent must program welding trajectory and export results."
