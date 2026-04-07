#!/bin/bash
# Setup script for configure_prosthetic_tactile_sensors task
# Generates a starting Webots world with kinematic bodies instead of sensors

echo "=== Setting up configure_prosthetic_tactile_sensors task ==="

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

# Create working directories
mkdir -p /home/ga/webots_projects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/webots_projects /home/ga/Desktop

USER_WORLD="/home/ga/webots_projects/prosthetic_hand_test.wbt"

# Generate the starting world file
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 32
  title "Prosthetic Grasp Test"
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.2
  position 0.6 0.5 0.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 1 1
}
DEF TEST_EGG Solid {
  translation 0 0.04 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.95 0.85 0.75
        roughness 0.5
      }
      geometry Sphere {
        radius 0.04
      }
    }
  ]
  name "test_egg"
  boundingObject Sphere {
    radius 0.04
  }
}
DEF INDEX_TIP Solid {
  translation 0.045 0.04 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.2 0.2
        roughness 0.8
      }
      geometry Box {
        size 0.01 0.06 0.02
      }
    }
  ]
  name "index_tip"
  boundingObject Box {
    size 0.01 0.06 0.02
  }
}
DEF THUMB_TIP Solid {
  translation -0.045 0.04 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.2 0.2
        roughness 0.8
      }
      geometry Box {
        size 0.01 0.06 0.02
      }
    }
  ]
  name "thumb_tip"
  boundingObject Box {
    size 0.01 0.06 0.02
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Remove any previous output file
rm -f /home/ga/Desktop/prosthetic_grasp_test.wbt

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch Webots with the starting world
echo "Launching Webots..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent should:"
echo "  1. Change basicTimeStep to 16"
echo "  2. Add Physics to TEST_EGG with mass 0.05"
echo "  3. Convert INDEX_TIP and THUMB_TIP to TouchSensors"
echo "  4. Set type to 'force-3d' and resolution to 0.001"
echo "  5. Save to /home/ga/Desktop/prosthetic_grasp_test.wbt"