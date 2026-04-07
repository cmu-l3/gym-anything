#!/bin/bash
echo "=== Setting up collision_config_map task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files (Anti-gaming check)
rm -f /home/ga/Documents/CoppeliaSim/exports/collision_map.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/collision_report.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/collision_config_map_start_ts

# Launch CoppeliaSim with robot scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" -path "*/messaging/*" 2>/dev/null | head -1)
if [ -z "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene not found, launching empty"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/collision_config_map_start_screenshot.png

echo "=== Setup Complete ==="
echo "Robot arm scene loaded. Agent must place obstacles, run collision sweep, and export results."