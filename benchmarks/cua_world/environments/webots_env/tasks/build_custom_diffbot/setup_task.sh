#!/bin/bash
echo "=== Setting up build_custom_diffbot task ==="

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

mkdir -p /home/ga/webots_projects
chown ga:ga /home/ga/webots_projects

USER_WORLD="/home/ga/webots_projects/empty_arena.wbt"

# Create a minimal starting world for building from scratch
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 32
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.2
  position 1.5 1.0 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 2 2
}
EOF
chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Clean up any previous output
rm -f /home/ga/Desktop/my_robot.wbt

# Launch Webots
echo "Launching Webots with empty arena..."
launch_webots_with_world "$USER_WORLD"

sleep 5
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="