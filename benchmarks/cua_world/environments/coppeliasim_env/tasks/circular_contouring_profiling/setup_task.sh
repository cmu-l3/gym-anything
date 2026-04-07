#!/bin/bash
echo "=== Setting up circular_contouring_profiling task ==="

source /workspace/scripts/task_utils.sh

# Create exports directory and ensure permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files to prevent anti-gaming
rm -f /home/ga/Documents/CoppeliaSim/exports/contouring_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/contouring_report.json 2>/dev/null || true

# Record task start timestamp for freshness checks
date +%s > /tmp/circular_contouring_profiling_start_ts

# Launch CoppeliaSim with the movementViaRemoteApi scene (contains a UR5 arm)
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Target scene not found, launching empty scene"
    launch_coppeliasim
fi

# Focus and maximize the application
focus_coppeliasim
maximize_coppeliasim

# Give UI time to stabilize and dismiss popups
sleep 2
dismiss_dialogs
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/circular_contouring_profiling_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with the UR5 robot arm scene."
echo "Agent must program a circular trajectory at multiple speeds and export tracking data."