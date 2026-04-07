#!/bin/bash
echo "=== Setting up configure_fpv_camera_optics task ==="

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

# Create the starting world programmatically to ensure a clean, known state
mkdir -p /home/ga/webots_projects/worlds
USER_WORLD="/home/ga/webots_projects/worlds/drone_racing_synthetic.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.1 0.96 0.25 1.75
  position 1.5 1.2 -1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 10 10
}
DEF RACING_DRONE Robot {
  translation 0 0.5 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.1 0.1
        roughness 0.5
        metalness 0.5
      }
      geometry Box {
        size 0.3 0.1 0.3
      }
    }
    DEF fpv_camera Camera {
      translation 0.15 0 0
      name "fpv_camera"
      width 1280
      height 720
      fieldOfView 1.5
    }
  ]
  name "racing_drone"
  physics Physics {
    mass 1.0
  }
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous output file
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/drone_fpv_realistic.wbt

# Launch Webots with the synthetic drone world
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
echo "Loaded: $USER_WORLD"
echo "Target output: /home/ga/Desktop/drone_fpv_realistic.wbt"