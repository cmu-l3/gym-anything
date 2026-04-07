#!/bin/bash
# Setup script for configure_spherical_mobile_mapping task

echo "=== Setting up configure_spherical_mobile_mapping task ==="

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

USER_WORLD="/home/ga/webots_projects/mobile_mapping.wbt"

# Generate the starting world with placeholder parameters
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 16
  gpsCoordinateSystem "local"
  gpsReference 0 0 0
}
Viewpoint {
  orientation -0.15 0.96 0.22 1.3
  position 8 5 -10
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 50 50
}
DEF MAPPING_VEHICLE Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
      }
      geometry Box {
        size 2 0.5 4
      }
    }
    DEF pano_camera Camera {
      translation 0 1.5 0
      name "pano_camera"
      fieldOfView 1.5708
      width 800
      height 600
      projection "planar"
    }
    DEF roof_lidar Lidar {
      translation 0 1.6 0
      name "roof_lidar"
      fieldOfView 1.5708
      horizontalResolution 512
      numberOfLayers 16
    }
    GPS {
      translation 0 1.5 0
      name "gps"
    }
  ]
  name "mapping_vehicle"
  boundingObject Box {
    size 2 0.5 4
  }
  physics Physics {
    density -1
    mass 1500
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed and remove any previous output
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/spherical_mapping.wbt

# Launch Webots with the scenario world
echo "Launching Webots with mobile mapping scenario world..."
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
echo "Target output: /home/ga/Desktop/spherical_mapping.wbt"