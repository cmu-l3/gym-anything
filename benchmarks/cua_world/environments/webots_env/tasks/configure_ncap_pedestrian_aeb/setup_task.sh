#!/bin/bash
echo "=== Setting up configure_ncap_pedestrian_aeb task ==="

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

# Create the task's custom world file
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/ncap_aeb_test.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "webots://projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "webots://projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "webots://projects/objects/floors/protos/RectangleArena.proto"
EXTERNPROTO "webots://projects/objects/humans/protos/Pedestrian.proto"

WorldInfo {
  basicTimeStep 16
  title "Euro NCAP Pedestrian AEB Test"
}
Viewpoint {
  position -12 6 8
  orientation -0.25 0.9 0.35 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 50 50
}
DEF EGO_VEHICLE Robot {
  translation -15 0 0.5
  children [
    DEF front_camera Camera {
      translation 2 0 1
      width 1280
      height 720
      recognition NULL
    }
  ]
}
DEF NCAP_TARGET Pedestrian {
  translation 10 3 0
  shirtColor 0.2 0.2 0.2
  speed 0.8
  trajectory []
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/ncap_aeb_configured.wbt

# Launch Webots with the scenario world
echo "Launching Webots with NCAP scenario world..."
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
echo "Agent should find nodes in the scene tree and reconfigure:"
echo "  - NCAP_TARGET: speed=1.5, shirtColor=1 0.5 0, trajectory=[0 0 0, 0 -6 0]"
echo "  - front_camera: change recognition from NULL to a Recognition node"
echo "  - Save to: /home/ga/Desktop/ncap_aeb_configured.wbt"