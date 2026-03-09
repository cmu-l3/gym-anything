#!/bin/bash
# Setup script for setup_pioneer_terrain_physics task
# Loads the Pioneer 3-AT field robot world with incorrect physics parameters.
# The agent must correct robot mass and add ContactProperties.

echo "=== Setting up setup_pioneer_terrain_physics task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

# Copy the task's custom world file to a writable location
TASK_WORLD="/workspace/tasks/setup_pioneer_terrain_physics/data/pioneer_field.wbt"
USER_WORLD="/home/ga/webots_projects/pioneer_field.wbt"

if [ ! -f "$TASK_WORLD" ]; then
    echo "ERROR: Task world file not found at $TASK_WORLD"
    exit 1
fi

mkdir -p /home/ga/webots_projects
cp "$TASK_WORLD" "$USER_WORLD"
chown ga:ga "$USER_WORLD"

# Record baseline: verify the world has the wrong (starting) physics values
echo "Verifying starting world state..."
if grep -q "mass 1.0" "$USER_WORLD"; then
    echo "Baseline confirmed: robot mass is 1.0 (needs to be changed to 12.5)"
else
    echo "INFO: Checking mass in world file:"
    grep "mass " "$USER_WORLD" | head -5
fi

# Confirm no ContactProperties in starting state
if grep -q "ContactProperties" "$USER_WORLD"; then
    echo "WARNING: ContactProperties already present — this is unexpected in starting state"
else
    echo "Baseline confirmed: no ContactProperties in starting world (needs to be added)"
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/pioneer_terrain.wbt

# Launch Webots with the Pioneer field world
echo "Launching Webots with Pioneer field world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent should:"
echo "  1. Find PIONEER_ROBOT → Physics node → change mass from 1.0 to 12.5"
echo "  2. Add ContactProperties to WorldInfo with coulombFriction=0.7, softness=0.001"
echo "  3. Save to /home/ga/Desktop/pioneer_terrain.wbt"
