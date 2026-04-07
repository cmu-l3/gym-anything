#!/bin/bash
echo "=== Setting up configure_mars_rover_physics task ==="

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

# Generate the starting world file with incorrect parameters
USER_WORLD="/home/ga/webots_projects/mars_rover_unconfigured.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectArena.proto"

WorldInfo {
  basicTimeStep 64
  gravity 9.81
}
Viewpoint {
  orientation -0.2 0.9 0.3 1.2
  position 4.0 3.0 4.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectArena {
  floorSize 10 10
  floorTileSize 1 1
  floorAppearance PBRAppearance {
    baseColor 0.6 0.3 0.2
    roughness 0.9
    metalness 0
  }
}
DEF MARS_ROVER Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
        roughness 0.5
        metalness 0.5
      }
      geometry Box {
        size 0.5 0.2 0.8
      }
    }
    DEF nav_camera Camera {
      translation 0 0.2 0.3
      name "nav_camera"
      width 256
      height 128
      fieldOfView 1.047
    }
  ]
  boundingObject Box {
    size 0.5 0.2 0.8
  }
  physics Physics {
    density -1
    mass 50.0
  }
  controller "<none>"
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory and remove any existing solution file
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/mars_rover.wbt

# Launch Webots with the scenario world
echo "Launching Webots with unconfigured Mars rover world..."
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
echo "Starting parameters (WRONG):"
echo "  - Gravity: 9.81"
echo "  - Timestep: 64"
echo "  - Camera: 256x128"
echo "  - Mass: 50.0"
echo "  - ContactProperties: None"