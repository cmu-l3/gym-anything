#!/bin/bash
echo "=== Setting up monte_carlo_pose_uncertainty task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/mc_samples.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/uncertainty_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/mc_uncertainty_start_ts

# STEP 3: Launch CoppeliaSim with a scene containing a robot arm (UR5)
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Default scene not found, launching empty scene"
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
take_screenshot /tmp/mc_uncertainty_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with the robot arm scene."
echo "Agent must perform Monte Carlo kinematic sampling via ZMQ API."