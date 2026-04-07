#!/bin/bash
echo "=== Setting up obstacle_path_planning task ==="

source /workspace/scripts/task_utils.sh

# Create output directories and set ownership
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/obstacle_path.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/path_planning_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/task_start_ts.txt

# STEP 3: Launch CoppeliaSim with the movementViaRemoteApi scene
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

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must build obstacles, execute path, and save results."