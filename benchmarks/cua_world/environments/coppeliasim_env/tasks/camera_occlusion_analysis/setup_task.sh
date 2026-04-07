#!/bin/bash
echo "=== Setting up camera_occlusion_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create export directory
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing files (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/occlusion_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/occlusion_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/camera_occlusion_analysis_start_ts

# Launch CoppeliaSim with a scene containing a robot arm
SCENE="/opt/CoppeliaSim/scenes/messaging/movementViaRemoteApi.ttt"
if [ ! -f "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

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
take_screenshot /tmp/camera_occlusion_analysis_start.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must compute camera occlusion and export data."