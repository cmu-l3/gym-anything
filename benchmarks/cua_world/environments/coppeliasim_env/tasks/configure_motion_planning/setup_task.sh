#!/bin/bash
echo "=== Setting up coordinate_multi_robot task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Clean any pre-existing output
rm -f /home/ga/Documents/CoppeliaSim/exports/multi_robot_done.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# Launch CoppeliaSim with the movementViaRemoteApi scene (3 robot arms)
SCENE="/opt/CoppeliaSim/scenes/messaging/movementViaRemoteApi.ttt"
if [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "WARNING: movementViaRemoteApi.ttt not found, trying alternatives"
    for alt in /opt/CoppeliaSim/scenes/kinematics/twoRobotsIK.ttt \
               /opt/CoppeliaSim/scenes/kinematics/smoothMovementsInFkAndIk.ttt; do
        if [ -f "$alt" ]; then
            SCENE="$alt"
            launch_coppeliasim "$alt"
            break
        fi
    done
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
echo "Multi-robot scene loaded. Agent must coordinate 3 robots via ZMQ API."
