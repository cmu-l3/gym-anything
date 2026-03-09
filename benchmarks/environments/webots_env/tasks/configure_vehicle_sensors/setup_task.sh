#!/bin/bash
# Setup script for configure_vehicle_sensors task
# Loads the AV sensor configuration world (real Webots built-in node types)
# and records baseline state before agent begins.

echo "=== Setting up configure_vehicle_sensors task ==="

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
# This world uses only standard Webots built-in node types (Robot, Camera, Lidar, GPS)
# so it works with any Webots R2023b installation without additional PROTOs.
TASK_WORLD="/workspace/tasks/configure_vehicle_sensors/data/av_scenario.wbt"
USER_WORLD="/home/ga/webots_projects/av_scenario.wbt"

if [ ! -f "$TASK_WORLD" ]; then
    echo "ERROR: Task world file not found at $TASK_WORLD"
    exit 1
fi

mkdir -p /home/ga/webots_projects
cp "$TASK_WORLD" "$USER_WORLD"
chown ga:ga "$USER_WORLD"

# Record baseline: verify the world has the wrong (starting) camera and lidar values
echo "Verifying starting world state..."
if grep -q "width 128" "$USER_WORLD"; then
    echo "Baseline confirmed: camera width is 128 (needs to be changed to 640)"
else
    echo "WARNING: Expected 'width 128' not found in starting world"
    grep "width" "$USER_WORLD" || echo "No width field found"
fi

if grep -q "numberOfLayers 4" "$USER_WORLD"; then
    echo "Baseline confirmed: lidar numberOfLayers is 4 (needs to be changed to 16)"
else
    echo "WARNING: Expected 'numberOfLayers 4' not found in starting world"
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/av_sensors_configured.wbt

# Launch Webots with the AV scenario world
echo "Launching Webots with AV scenario world..."
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
echo "Agent should find sensors in the scene tree and reconfigure:"
echo "  - front_camera: width=128, height=64 → must change to 640x480"
echo "  - velodyne_lidar: numberOfLayers=4, maxRange=20 → must change to 16 layers, 100m"
echo "  - Save to: /home/ga/Desktop/av_sensors_configured.wbt"
