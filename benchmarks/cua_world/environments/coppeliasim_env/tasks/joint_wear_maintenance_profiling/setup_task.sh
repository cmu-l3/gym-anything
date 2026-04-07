#!/bin/bash
echo "=== Setting up joint_wear_maintenance_profiling task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/trajectory_trace.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/joint_wear_log.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/maintenance_schedule.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/task_start_ts

# STEP 3: Launch CoppeliaSim with the movementViaRemoteApi scene
# (has a 6-DOF robot arm ready to be controlled)
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene not found, launching empty scene"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Robot arm scene loaded. Agent must simulate 5 cycles, log wear data, and export schedule."