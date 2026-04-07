#!/bin/bash
# Setup script for configure_rgbd_mapping_sensors task
# Generates a clean starting world with a mobile robot and misconfigured RGB-D sensors.

echo "=== Setting up configure_rgbd_mapping_sensors task ==="

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

# Create the starting world programmatically using standard Webots nodes
USER_WORLD="/home/ga/webots_projects/rgbd_mapping.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.9 0.3 1.5
  position 2.5 2.0 2.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
        metalness 0.1
      }
      geometry Box {
        size 0.2 0.1 0.3
      }
    }
    RangeFinder {
      translation 0.0 0.065 0.0
      name "depth_camera"
      width 128
      height 96
      fieldOfView 0.5
      minRange 0.01
      maxRange 3.0
    }
    Camera {
      translation 0.02 0.05 0.0
      name "rgb_camera"
      width 128
      height 96
      fieldOfView 0.5
    }
  ]
  name "MAPPING_ROBOT"
  controller "<none>"
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/rgbd_mapping_robot.wbt

# Launch Webots with the scenario world
echo "Launching Webots with RGB-D mapping scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for verification
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent task:"
echo "  - Configure 'depth_camera' to D435 specs (640x480, max=10, min=0.3, fov=1.5184)"
echo "  - Configure 'rgb_camera' to D435 specs (640x480, fov=1.2040)"
echo "  - Match rgb_camera translation to depth_camera for co-location"
echo "  - Save to /home/ga/Desktop/rgbd_mapping_robot.wbt"