#!/bin/bash
# Setup script for configure_airdrop_damping_physics task

echo "=== Setting up configure_airdrop_damping_physics task ==="

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

# Dynamically generate the starting world
USER_WORLD="/home/ga/webots_projects/airdrop_test.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.05 0.95 0.3 2.5
  position 10 105 10
}
TexturedBackground {}
TexturedBackgroundLight {}
RectangleArena {
  floorSize 200 200
}
DEF SENSOR_POD Robot {
  translation 0 100 0
  children [
    Solid {
      children [
        Shape {
          appearance PBRAppearance {
            baseColor 0.8 0.2 0.2
            roughness 0.5
            metalness 0.5
          }
          geometry Cylinder {
            height 0.5
            radius 0.2
          }
        }
      ]
    }
    DEF ALTIMETER DistanceSensor {
      translation 0 -0.25 0
      name "ALTIMETER"
      type "sonar"
      maxRange 10.0
    }
  ]
  boundingObject Cylinder {
    height 0.5
    radius 0.2
  }
  physics Physics {
    mass 1.0
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_time

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/airdrop_configured.wbt

# Launch Webots with the generated world
echo "Launching Webots with airdrop scenario world..."
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