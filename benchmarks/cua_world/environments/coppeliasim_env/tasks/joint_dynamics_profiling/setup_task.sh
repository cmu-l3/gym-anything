#!/bin/bash
echo "=== Setting up joint_dynamics_profiling task ==="

source /workspace/scripts/task_utils.sh

# Create output directories with appropriate permissions
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/dynamics_profile.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/dynamics_report.json 2>/dev/null || true

# Record task start timestamp for verification
date +%s > /tmp/joint_dynamics_profiling_start_ts

# Launch CoppeliaSim with the required robot arm scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" -path "*/messaging/*" 2>/dev/null | head -1)
if [ -z "$SCENE" ]; then
    # Fallback if standard path varies
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "movementViaRemoteApi scene not found, launching empty"
    launch_coppeliasim
fi

# Make the interface ready for the agent
focus_coppeliasim
maximize_coppeliasim
sleep 2
dismiss_dialogs

# Take initial state screenshot
sleep 2
take_screenshot /tmp/joint_dynamics_profiling_start.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with the robot arm scene."
echo "Agent must programmatically profile joint dynamics and generate the requested reports."