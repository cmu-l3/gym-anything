#!/bin/bash
echo "=== Setting up conveyor_line_tracking task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing files
rm -f /home/ga/Documents/CoppeliaSim/exports/conveyor_tracking.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/tracking_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/conveyor_line_tracking_start_ts

# Launch CoppeliaSim with movementViaRemoteApi scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" -path "*/messaging/*" 2>/dev/null | head -1)
if [ -z "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "movementViaRemoteApi scene not found, launching empty"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/conveyor_line_tracking_start_screenshot.png

echo "=== Setup Complete ==="