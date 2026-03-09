#!/bin/bash
echo "=== Setting up change_timestep task ==="

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

# Copy the official Webots soccer demo world to user's writable directory
# This is real data from the Webots distribution - an official demo simulation
# featuring two robot teams playing soccer with a supervisor controller
DEMO_WORLD="$WEBOTS_HOME/projects/samples/demos/worlds/soccer.wbt"
USER_WORLD="/home/ga/webots_projects/soccer.wbt"

if [ ! -f "$DEMO_WORLD" ]; then
    echo "soccer.wbt not found at expected path, searching..."
    DEMO_WORLD=$(find "$WEBOTS_HOME" -name "soccer.wbt" -type f 2>/dev/null | head -1)
    if [ -z "$DEMO_WORLD" ]; then
        echo "ERROR: soccer.wbt not found anywhere in $WEBOTS_HOME"
        exit 1
    fi
    echo "Found at: $DEMO_WORLD"
fi

# Copy demo world and its dependencies to writable location
mkdir -p /home/ga/webots_projects
cp "$DEMO_WORLD" "$USER_WORLD"

# Copy associated protos and textures (Webots worlds reference relative paths)
DEMO_DIR="$(dirname "$(dirname "$DEMO_WORLD")")"
if [ -d "$DEMO_DIR/controllers" ]; then
    cp -r "$DEMO_DIR/controllers" /home/ga/webots_projects/ 2>/dev/null || true
fi
if [ -d "$DEMO_DIR/protos" ]; then
    cp -r "$DEMO_DIR/protos" /home/ga/webots_projects/ 2>/dev/null || true
fi

chown -R ga:ga /home/ga/webots_projects

# Record baseline: verify the world has basicTimeStep 32
echo "Checking baseline world state..."
if grep -q "basicTimeStep 32" "$USER_WORLD"; then
    echo "Baseline confirmed: basicTimeStep is 32"
else
    echo "WARNING: basicTimeStep is not 32, checking actual value:"
    grep "basicTimeStep" "$USER_WORLD" || echo "basicTimeStep not found in world file"
fi

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch Webots with the soccer world
echo "Launching Webots with soccer.wbt..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "  1. Click WorldInfo in the scene tree"
echo "  2. Change basicTimeStep from 32 to 64"
echo "  3. Save as /home/ga/Desktop/modified_soccer.wbt"
