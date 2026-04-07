#!/bin/bash
echo "=== Setting up light_curtain_safety_validation task ==="

source /workspace/scripts/task_utils.sh

# Create exports directory and set ownership
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files before taking timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/light_curtain_breaches.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/safety_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/light_curtain_task_start_ts

# Launch CoppeliaSim with the movementViaRemoteApi scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene not found, launching empty scene"
    launch_coppeliasim
fi

# Focus and maximize the window
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/light_curtain_task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Agent must build the virtual light curtain and run the safety test."