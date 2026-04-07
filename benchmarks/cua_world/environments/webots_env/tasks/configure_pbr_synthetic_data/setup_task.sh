#!/bin/bash
echo "=== Setting up configure_pbr_synthetic_data task ==="

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

# Create the starting world file with legacy Appearance nodes
PROJECT_DIR="/home/ga/webots_projects"
USER_WORLD="$PROJECT_DIR/recycling_sort.wbt"

mkdir -p "$PROJECT_DIR"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 32
}
Viewpoint {
  orientation -0.25 0.9 0.3 1.2
  position 1.5 1.0 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 2 2
}
DEF METAL_CAN Solid {
  translation 0 0.06 0
  children [
    Shape {
      appearance Appearance {
        material Material {
          diffuseColor 0.8 0.8 0.8
        }
      }
      geometry Cylinder {
        height 0.12
        radius 0.03
      }
    }
  ]
}
DEF PLASTIC_BOTTLE Solid {
  translation 0.3 0.1 -0.2
  children [
    Shape {
      appearance Appearance {
        material Material {
          diffuseColor 0.2 0.6 1.0
        }
      }
      geometry Cylinder {
        height 0.2
        radius 0.04
      }
    }
  ]
}
DEF CARDBOARD_BOX Solid {
  translation -0.3 0.1 -0.1
  children [
    Shape {
      appearance Appearance {
        material Material {
          diffuseColor 0.7 0.5 0.3
        }
      }
      geometry Box {
        size 0.2 0.2 0.2
      }
    }
  ]
}
EOF

chown -R ga:ga "$PROJECT_DIR"

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/recycling_pbr.wbt

# Launch Webots with the scenario world
echo "Launching Webots with the legacy shading world..."
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
echo "Target task: Upgrade Appearance to PBRAppearance for METAL_CAN, PLASTIC_BOTTLE, CARDBOARD_BOX."