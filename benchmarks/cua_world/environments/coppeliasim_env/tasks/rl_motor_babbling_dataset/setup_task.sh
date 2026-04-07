#!/bin/bash
echo "=== Setting up rl_motor_babbling_dataset task ==="

source /workspace/scripts/task_utils.sh

# Create clean output directories
export_dir="/home/ga/Documents/CoppeliaSim/exports"
rm -rf "$export_dir" 2>/dev/null || true
mkdir -p "$export_dir/images"
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/rl_motor_babbling_start_ts

# Launch CoppeliaSim with a robot arm scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene not found, launching empty scene"
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
take_screenshot /tmp/rl_motor_babbling_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with robot arm scene."
echo "Agent must add a Vision Sensor, script a motor babbling loop, and export a multimodal RL dataset."