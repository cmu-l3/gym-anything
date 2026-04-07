#!/bin/bash
# Setup script for create_terrain_testworld task
# Creates a minimal blank world and launches Webots.

echo "=== Setting up create_terrain_testworld task ==="

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

# Create a clean starting project structure
mkdir -p /home/ga/webots_projects/controllers
mkdir -p /home/ga/webots_projects/worlds
chown -R ga:ga /home/ga/webots_projects

USER_WORLD="/home/ga/webots_projects/worlds/empty_terrain_start.wbt"

# Generate a minimal blank world programmatically
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.95 0.15 1.0
  position 12.0 8.0 12.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
EOF
chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming (ensure agent creates the file AFTER start)
date +%s > /tmp/task_start_time.txt

# Create Desktop directory if needed and remove any previous output file
mkdir -p /home/ga/Desktop
rm -f /home/ga/Desktop/terrain_nav_test.wbt
chown ga:ga /home/ga/Desktop

# Launch Webots with the blank world
echo "Launching Webots with empty starting world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing the empty environment
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent must build the ElevationGrid, configure collision, place Pioneer3at, and save to desktop."