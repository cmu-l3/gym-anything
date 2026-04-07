#!/bin/bash
echo "=== Setting up pick_and_place_objects task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Clean any pre-existing output
rm -f /home/ga/Documents/CoppeliaSim/exports/pick_place_done.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# Launch CoppeliaSim with the pick-and-place demo scene
SCENE="/opt/CoppeliaSim/scenes/pickAndPlaceDemo.ttt"
if [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "WARNING: pickAndPlaceDemo.ttt not found"
    launch_coppeliasim
fi

# Record loaded scene
echo "${SCENE}" > /tmp/loaded_scene_path

# Focus and maximize
focus_coppeliasim
maximize_coppeliasim

# Dismiss any dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Pick-and-place scene loaded. Agent must teleoperate Ragnar robot via ZMQ API."
