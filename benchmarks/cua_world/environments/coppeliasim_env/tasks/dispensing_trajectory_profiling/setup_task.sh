#!/bin/bash
echo "=== Setting up dispensing_trajectory_profiling task ==="

source /workspace/scripts/task_utils.sh

# Create required output directory
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing files to prevent gaming
rm -f /home/ga/Documents/CoppeliaSim/exports/dispensing_profile.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/dispensing_report.json 2>/dev/null || true

# Record task start timestamp for freshness verification
date +%s > /tmp/task_start_ts

# Launch CoppeliaSim with the movementViaRemoteApi scene
# This scene comes pre-loaded with a robot arm suitable for trajectory programming
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Warning: Target scene not found, launching empty scene"
    launch_coppeliasim
fi

# Ensure window is visible and focused
focus_coppeliasim
maximize_coppeliasim

# Let UI settle and dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot as evidence
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must implement the dispensing trajectory control script."