#!/bin/bash
echo "=== Setting up scene_spatial_audit task ==="

source /workspace/scripts/task_utils.sh

# Create workspace directory
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files (Anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/scene_inventory.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/spatial_analysis.json 2>/dev/null || true

# STEP 2: Record task start timestamp for file verification
date +%s > /tmp/scene_spatial_audit_start_ts

# STEP 3: Launch CoppeliaSim with the default multi-arm movement scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Primary scene not found, falling back to empty scene"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot as evidence
sleep 2
take_screenshot /tmp/scene_spatial_audit_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim loaded. Agent must connect via ZMQ Remote API to perform spatial audit."