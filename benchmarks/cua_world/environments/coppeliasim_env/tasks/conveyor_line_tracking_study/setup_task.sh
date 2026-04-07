#!/bin/bash
echo "=== Setting up conveyor_line_tracking_study task ==="

source /workspace/scripts/task_utils.sh

# Create exports directory and ensure permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove any pre-existing output files (Anti-gaming check)
rm -f /home/ga/Documents/CoppeliaSim/exports/tracking_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/tracking_report.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/line_tracking_final.ttt 2>/dev/null || true

# Record task start timestamp for file creation validation
date +%s > /tmp/conveyor_task_start_ts

# Locate and launch the target scene
SCENE="/opt/CoppeliaSim/scenes/messaging/movementViaRemoteApi.ttt"
if [ ! -f "$SCENE" ]; then
    # Fallback search
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "WARNING: target scene not found, launching empty scene"
    launch_coppeliasim
fi

# Prepare the UI
focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial state screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent must write a Python script using ZMQ Remote API to simulate line tracking."