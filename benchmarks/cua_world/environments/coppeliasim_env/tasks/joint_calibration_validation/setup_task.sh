#!/bin/bash
echo "=== Setting up joint_calibration_validation task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output BEFORE timestamp
rm -f /home/ga/Documents/CoppeliaSim/exports/calibration_results.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/calibration_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/joint_calibration_validation_start_ts

# STEP 3: Launch with 3-robot-arm scene (agent must select one robot for calibration)
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
take_screenshot /tmp/joint_calibration_validation_start_screenshot.png

echo "=== Setup Complete ==="
echo "Robot arm scene loaded. Agent must perform 10-configuration calibration validation."
