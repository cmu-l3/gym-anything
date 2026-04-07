#!/bin/bash
# Setup script for configure_patrol_sensors task

echo "=== Setting up configure_patrol_sensors task ==="

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

# Create the working directory
mkdir -p /home/ga/webots_projects
chown ga:ga /home/ga/webots_projects

USER_WORLD="/home/ga/webots_projects/patrol_scenario.wbt"

# Generate the starting world dynamically to ensure it has the exact incorrect starting state
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.95 0.15 1.2
  position 12 8 12
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 20 20
}
DEF PATROL_ROBOT Robot {
  translation 0 0.1 0
  children [
    Radar {
      name "patrol_radar"
      maxRange 5
      horizontalFieldOfView 0.5
      maxSpeed 5
    }
    RangeFinder {
      name "obstacle_rangefinder"
      width 32
      height 16
      maxRange 2
    }
    Solid {
      translation 0 0.2 0
      children [
        Shape {
          appearance PBRAppearance {
            baseColor 0.2 0.2 0.8
            roughness 0.5
            metalness 0.5
          }
          geometry Cylinder {
            height 0.4
            radius 0.15
          }
        }
      ]
    }
  ]
  boundingObject Cylinder {
    height 0.4
    radius 0.15
  }
  physics Physics {
    mass 20
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory and remove any previous output file
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/patrol_robot_configured.wbt

# Launch Webots with the scenario world
echo "Launching Webots with patrol scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the Webots window
focus_webots

# Dismiss any remaining pop-ups or dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Loaded: $USER_WORLD"
echo "Agent instructions:"
echo "1. Radar 'patrol_radar': maxRange=50.0, horizontalFieldOfView=2.094, maxSpeed=30.0"
echo "2. RangeFinder 'obstacle_rangefinder': width=256, height=128, maxRange=10.0"
echo "3. PATROL_ROBOT translation: 5.0 0.1 5.0"
echo "4. Save world to: /home/ga/Desktop/patrol_robot_configured.wbt"