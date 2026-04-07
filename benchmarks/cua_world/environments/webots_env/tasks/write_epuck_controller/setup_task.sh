#!/bin/bash
# Setup script for write_epuck_controller task
# Creates a Webots project structure, generates a world with an e-puck and obstacles,
# and leaves the controller directory empty for the agent to fill.

echo "=== Setting up write_epuck_controller task ==="

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

# Define project paths
PROJECT_DIR="/home/ga/webots_projects/epuck_obstacle"
WORLDS_DIR="$PROJECT_DIR/worlds"
CTRL_DIR="$PROJECT_DIR/controllers/obstacle_avoider"
WORLD_FILE="$WORLDS_DIR/epuck_arena.wbt"

# Create project structure
mkdir -p "$WORLDS_DIR"
mkdir -p "$CTRL_DIR"

# Generate the Webots world file using standard Webots R2023b EXTERNPROTOs
cat > "$WORLD_FILE" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/robots/gctronic/e-puck/protos/E-puck.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/factory/containers/protos/WoodenBox.proto"

WorldInfo {
  basicTimeStep 16
  title "E-puck Obstacle Avoidance"
}
Viewpoint {
  orientation -0.57735 0.57735 0.57735 2.0944
  position 1.2 1.2 1.2
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 1 1
}
E-puck {
  translation 0 0 0
  controller "obstacle_avoider"
}
WoodenBox {
  translation 0.3 0.3 0.05
  size 0.1 0.1 0.1
}
WoodenBox {
  translation -0.2 0.35 0.05
  size 0.1 0.1 0.1
  mass 2
}
WoodenBox {
  translation 0.2 -0.2 0.05
  size 0.1 0.1 0.1
  mass 2
}
EOF

# Ensure the controller directory is completely empty
rm -f "$CTRL_DIR"/* 2>/dev/null || true

# Set permissions
chown -R ga:ga "/home/ga/webots_projects"

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/epuck_avoidance.wbt

# Launch Webots with the created world
echo "Launching Webots with e-puck arena world..."
launch_webots_with_world "$WORLD_FILE"

sleep 6

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $WORLD_FILE"
echo "Project dir: $PROJECT_DIR"
echo "Agent must create: $CTRL_DIR/obstacle_avoider.py"