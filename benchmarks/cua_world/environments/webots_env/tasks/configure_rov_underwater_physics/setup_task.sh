#!/bin/bash
# Setup script for configure_rov_underwater_physics task
# Generates a minimal underwater ROV scenario with intentionally flawed physics parameters.

echo "=== Setting up configure_rov_underwater_physics task ==="

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

# Create the task's custom world file programmatically to ensure it's exact
USER_WORLD="/home/ga/webots_projects/rov_scenario.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"

WorldInfo {
  basicTimeStep 16
  gravity 9.81
}
Viewpoint {
  orientation -0.15 0.9 0.4 1.7
  position 3.5 1.5 3.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
DEF ocean Fluid {
  description "ocean"
  density 1.0
  boundingObject Box {
    size 20 20 20
  }
}
DEF ROV_VEHICLE Robot {
  translation 0 0 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.2
        roughness 0.5
        metalness 0.5
      }
      geometry Cylinder {
        height 0.3
        radius 0.2
      }
    }
  ]
  name "BlueROV2"
  boundingObject Cylinder {
    height 0.3
    radius 0.2
  }
  physics Physics {
    density -1
    mass 150.0
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/rov_configured.wbt

# Launch Webots with the scenario world
echo "Launching Webots with ROV scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for visual validation of starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent should:"
echo "  1. Find 'ocean' Fluid node: change density from 1.0 -> 1025.0"
echo "  2. Find 'ROV_VEHICLE' Robot: change Physics mass from 150.0 -> 11.5"
echo "  3. Add 'Damping' to Physics: set linear and angular to 0.5"
echo "  4. Save to /home/ga/Desktop/rov_configured.wbt"