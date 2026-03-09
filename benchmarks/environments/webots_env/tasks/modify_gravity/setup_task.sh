#!/bin/bash
echo "=== Setting up modify_gravity task ==="

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
# with default Earth gravity (9.81) that the agent will change to Mars gravity (3.72)
DEMO_WORLD="$WEBOTS_HOME/projects/samples/demos/worlds/soccer.wbt"
USER_WORLD="/home/ga/webots_projects/gravity_world.wbt"

if [ ! -f "$DEMO_WORLD" ]; then
    echo "soccer.wbt not found, searching for alternatives with Earth gravity..."
    for candidate in "hexapod.wbt" "gantry.wbt"; do
        ALT="$WEBOTS_HOME/projects/samples/demos/worlds/$candidate"
        if [ -f "$ALT" ]; then
            DEMO_WORLD="$ALT"
            echo "Using alternative: $candidate"
            break
        fi
    done
fi

if [ ! -f "$DEMO_WORLD" ]; then
    echo "ERROR: No suitable world file found in Webots installation"
    exit 1
fi

# Copy demo world and its dependencies to writable location
mkdir -p /home/ga/webots_projects
cp "$DEMO_WORLD" "$USER_WORLD"

# Copy associated project files
DEMO_DIR="$(dirname "$(dirname "$DEMO_WORLD")")"
if [ -d "$DEMO_DIR/controllers" ]; then
    cp -rn "$DEMO_DIR/controllers" /home/ga/webots_projects/ 2>/dev/null || true
fi
if [ -d "$DEMO_DIR/protos" ]; then
    cp -rn "$DEMO_DIR/protos" /home/ga/webots_projects/ 2>/dev/null || true
fi

chown -R ga:ga /home/ga/webots_projects

# Record baseline: verify gravity is 9.81 (Earth default)
echo "Checking baseline world state..."
if grep -q "gravity 9.81" "$USER_WORLD"; then
    echo "Baseline confirmed: gravity is 9.81 (Earth)"
elif grep -q "gravity" "$USER_WORLD"; then
    echo "WARNING: gravity is not 9.81, checking actual value:"
    grep "gravity" "$USER_WORLD"
else
    echo "gravity not explicitly set (defaults to 9.81)"
fi

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch Webots with the demo world
echo "Launching Webots with demo world..."
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
echo "  2. Change gravity from 9.81 to 3.72 (Mars gravity)"
echo "  3. Save as /home/ga/Desktop/mars_gravity_world.wbt"
