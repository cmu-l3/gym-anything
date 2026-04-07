#!/bin/bash
echo "=== Setting up safety_zone_audit task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming check)
rm -f /home/ga/Documents/CoppeliaSim/exports/safety_zone_log.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/safety_compliance_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/safety_zone_audit_start_ts

# STEP 3: Launch CoppeliaSim with movementViaRemoteApi scene
SCENE="/opt/CoppeliaSim/scenes/messaging/movementViaRemoteApi.ttt"
if [ ! -f "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Scene not found, launching empty scene"
    launch_coppeliasim
fi

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/safety_zone_audit_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with the movementViaRemoteApi scene."
echo "Agent must perform safety zone compliance audit via Python ZMQ API."