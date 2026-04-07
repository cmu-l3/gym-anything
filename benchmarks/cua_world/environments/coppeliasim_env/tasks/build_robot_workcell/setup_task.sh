#!/bin/bash
echo "=== Setting up navigate_arm_around_obstacles task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Clean any pre-existing output
rm -f /home/ga/Documents/CoppeliaSim/exports/obstacle_nav_done.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# Launch CoppeliaSim with the obstacle avoidance IK scene
SCENE="/opt/CoppeliaSim/scenes/kinematics/obstacleAvoidanceAndIk.ttt"
if [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "WARNING: obstacleAvoidanceAndIk.ttt not found, trying alternatives"
    for alt in /opt/CoppeliaSim/scenes/kinematics/ikPathGeneration.ttt \
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
echo "Obstacle avoidance scene loaded. Agent must navigate robot arm via ZMQ API."
