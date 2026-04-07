#!/bin/bash
echo "=== Setting up hand_eye_calibration_dataset task ==="

source /workspace/scripts/task_utils.sh

# Create output directories and set permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove any pre-existing output files to prevent gaming
rm -f /home/ga/Documents/CoppeliaSim/exports/hand_eye_dataset.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/dataset_report.json 2>/dev/null || true

# Record task start timestamp for verification
date +%s > /tmp/hand_eye_calibration_start_ts

# Launch CoppeliaSim with a scene containing a robotic arm
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

# Focus and maximize the application window
focus_coppeliasim
maximize_coppeliasim

# Allow UI to stabilize and dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial state screenshot
sleep 2
take_screenshot /tmp/hand_eye_calibration_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must attach a camera, perform kinematic sweep, and record data."