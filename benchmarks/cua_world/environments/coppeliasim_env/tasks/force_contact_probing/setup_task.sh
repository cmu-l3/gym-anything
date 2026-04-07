#!/bin/bash
echo "=== Setting up force_contact_probing task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/contact_probing.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/probing_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/force_contact_probing_start_ts

# Launch CoppeliaSim with a scene containing a robot arm
SCENE="/opt/CoppeliaSim/scenes/messaging/movementViaRemoteApi.ttt"
if [ ! -f "$SCENE" ]; then
    # fallback: try alternate locations if specific path isn't mapped
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

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

# Take initial screenshot to prove app is open
sleep 2
take_screenshot /tmp/force_contact_probing_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with a robot arm scene."
echo "Agent must use ZMQ Remote API to set up the force probe, execute the routine, and export results."