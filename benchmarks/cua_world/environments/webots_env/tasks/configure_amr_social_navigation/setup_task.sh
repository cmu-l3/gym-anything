#!/bin/bash
echo "=== Setting up configure_amr_social_navigation task ==="

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

# Dynamically generate the baseline world file
USER_WORLD="/home/ga/webots_projects/hospital_corridor_test.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/humans/pedestrian/protos/Pedestrian.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 32
}
Viewpoint {
  orientation -0.2 0.9 0.3 1.2
  position 8.5 5.5 4.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 15 15
}
DEF DOCTOR Pedestrian {
  translation 5 2.5 0
  name "DOCTOR"
  controller "<none>"
  speed 0.5
}
DEF HOSPITAL_ROBOT Robot {
  translation 0 0 0
  name "HOSPITAL_ROBOT"
  children [
    DEF SAFETY_LIDAR Lidar {
      translation 0 0 0.05
      name "safety_lidar"
      fieldOfView 1.57
      horizontalResolution 256
    }
  ]
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/amr_social_navigation.wbt

# Launch Webots with the scenario world
echo "Launching Webots..."
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
echo "Agent should configure Pedestrian trajectory/speed and Lidar parameters."