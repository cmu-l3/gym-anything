#!/bin/bash
set -euo pipefail

echo "=== Setting up cobot_ssm_validation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create output directories with proper permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Anti-gaming. Remove any pre-existing output files before timestamping
rm -f /home/ga/Documents/CoppeliaSim/exports/ssm_telemetry.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/ssm_summary.json 2>/dev/null || true

# STEP 2: Record task start timestamp (crucial for verifying work was done during task)
date +%s > /tmp/cobot_ssm_start_ts

# STEP 3: Launch CoppeliaSim with an appropriate scene
# We provide the movementViaRemoteApi scene to give the agent a ready-to-move robot
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Target scene not found, launching empty scene"
    launch_coppeliasim
fi

# Focus, maximize, and dismiss startup popups
focus_coppeliasim
maximize_coppeliasim
sleep 2
dismiss_dialogs

# Take initial screenshot as evidence of starting state
sleep 2
take_screenshot /tmp/cobot_ssm_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must implement the SSM logic via Python ZMQ remote API."