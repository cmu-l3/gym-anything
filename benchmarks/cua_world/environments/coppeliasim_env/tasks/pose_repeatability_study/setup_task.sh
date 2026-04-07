#!/bin/bash
echo "=== Setting up pose_repeatability_study task ==="

source /workspace/scripts/task_utils.sh

# Create required output directory
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files before recording the timestamp (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/repeatability_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/repeatability_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/pose_repeatability_study_start_ts

# Launch CoppeliaSim with the movementViaRemoteApi scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene movementViaRemoteApi not found, launching empty scene"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

sleep 2
take_screenshot /tmp/pose_repeatability_study_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must write a Python script using ZMQ Remote API to perform the repeatability study and export results."