#!/bin/bash
echo "=== Setting up pid_joint_tuning_study task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/pid_tuning_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/pid_tuning_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/pid_tuning_start_ts

# Launch CoppeliaSim with the multi-arm scene so a robot is available
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" -path "*/messaging/*" 2>/dev/null | head -1)
if [ -z "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "movementViaRemoteApi scene not found, launching empty scene"
    launch_coppeliasim
fi

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/pid_tuning_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with robot arm scene."
echo "Agent must use ZMQ Remote API to perform PID joint tuning study and export results."