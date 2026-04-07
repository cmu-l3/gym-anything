#!/bin/bash
echo "=== Setting up cell_reach_optimization task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Clear any pre-existing output files before task start
rm -f /home/ga/Documents/CoppeliaSim/exports/placement_candidates.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/placement_recommendation.json 2>/dev/null || true

# STEP 2: Record task start timestamp for anti-gaming verification
date +%s > /tmp/cell_reach_optimization_start_ts

# STEP 3: Launch CoppeliaSim with the appropriate scene
# (movementViaRemoteApi contains a robot arm ready to be manipulated)
SCENE="/opt/CoppeliaSim/scenes/messaging/movementViaRemoteApi.ttt"
if [ ! -f "$SCENE" ]; then
    # Fallback search if path differs slightly
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading base robot scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "WARNING: Robot scene not found, launching empty scene"
    launch_coppeliasim
fi

# Maximize the window for visibility
focus_coppeliasim
maximize_coppeliasim

# Dismiss any startup dialogs (Welcome dialogs etc.)
sleep 2
dismiss_dialogs

# Take an initial screenshot as proof of starting state
sleep 2
take_screenshot /tmp/cell_reach_optimization_start.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running. Ready for base placement optimization."