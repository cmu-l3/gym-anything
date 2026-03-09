#!/bin/bash
echo "=== Setting up save_world_as task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Clean up any previous output
rm -f /home/ga/Documents/webots_projects/my_highway.wbt

# Ensure the output directory exists
mkdir -p /home/ga/Documents/webots_projects
chown -R ga:ga /home/ga/Documents/webots_projects

# Find the highway world file
# In Webots R2023b the file is "highway_overtake.wbt" under projects/vehicles/worlds/
HIGHWAY_WORLD=""
for CANDIDATE in \
    "$WEBOTS_HOME/projects/vehicles/worlds/highway_overtake.wbt" \
    "$WEBOTS_HOME/projects/samples/demos/worlds/highway_overtaking.wbt" \
    "$WEBOTS_HOME/projects/vehicles/worlds/highway_overtaking.wbt"; do
    if [ -f "$CANDIDATE" ]; then
        HIGHWAY_WORLD="$CANDIDATE"
        break
    fi
done

# If not found by known paths, search broadly
if [ -z "$HIGHWAY_WORLD" ]; then
    HIGHWAY_WORLD=$(find "$WEBOTS_HOME" -name "*highway*.wbt" -type f 2>/dev/null | head -1)
fi

if [ -z "$HIGHWAY_WORLD" ]; then
    echo "ERROR: No world file found in Webots installation"
    exit 1
fi

echo "Using world file: $HIGHWAY_WORLD"

# Launch Webots with the highway world
launch_webots_with_world "$HIGHWAY_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Webots is open with a highway world loaded."
echo "Agent should: File > Save World As > navigate to /home/ga/Documents/webots_projects/ > save as my_highway.wbt"
