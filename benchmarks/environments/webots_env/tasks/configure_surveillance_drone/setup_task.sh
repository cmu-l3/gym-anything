#!/bin/bash
# Setup script for configure_surveillance_drone task
# Loads the surveillance drone world with misconfigured camera, missing GPS,
# and wrong altitude. Agent must fix all three.

echo "=== Setting up configure_surveillance_drone task ==="

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
TASK_WORLD="/workspace/tasks/configure_surveillance_drone/data/drone_scenario.wbt"
USER_WORLD="/home/ga/webots_projects/drone_scenario.wbt"

if [ ! -f "$TASK_WORLD" ]; then
    echo "ERROR: Task world file not found at $TASK_WORLD"
    exit 1
fi

mkdir -p /home/ga/webots_projects
cp "$TASK_WORLD" "$USER_WORLD"
chown ga:ga "$USER_WORLD"

# Record baseline: verify starting state
echo "Verifying starting world state..."
if grep -q "width 320" "$USER_WORLD"; then
    echo "Baseline confirmed: camera width is 320 (needs to be 1280)"
else
    echo "INFO: checking camera width:"
    grep "width" "$USER_WORLD"
fi

if grep -q "height 240" "$USER_WORLD"; then
    echo "Baseline confirmed: camera height is 240 (needs to be 720)"
fi

if grep -q "translation 0 0 0.5" "$USER_WORLD"; then
    echo "Baseline confirmed: drone altitude is 0.5m (needs to be 5.0m)"
fi

if ! grep -q "GPS {" "$USER_WORLD"; then
    echo "Baseline confirmed: no GPS node present (needs to be added)"
else
    echo "WARNING: GPS already present in starting world — unexpected"
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/surveillance_drone.wbt

# Launch Webots with the drone scenario world
echo "Launching Webots with drone scenario world..."
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
echo "  1. Change surveillance_camera: width 320→1280, height 240→720, fieldOfView 1.5708→0.7854"
echo "  2. Add GPS node named 'gps' to SURVEILLANCE_DRONE children"
echo "  3. Change SURVEILLANCE_DRONE translation Z from 0.5 to 5.0"
echo "  4. Save to /home/ga/Desktop/surveillance_drone.wbt"
