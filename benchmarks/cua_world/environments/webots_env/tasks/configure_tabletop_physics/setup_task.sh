#!/bin/bash
# Setup script for configure_tabletop_physics task

echo "=== Setting up configure_tabletop_physics task ==="

source /workspace/scripts/task_utils.sh

# Webots setup
export LIBGL_ALWAYS_SOFTWARE=1
WEBOTS_HOME=$(detect_webots_home)

pkill -f "webots" 2>/dev/null || true
sleep 2

# Create the starting world file without physics or bounding objects
mkdir -p /home/ga/webots_projects
cat > /home/ga/webots_projects/tabletop_scene.wbt << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 32
}
Viewpoint {
  orientation -0.27 0.65 0.71 0.87
  position -1.2 -1.4 1.3
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 3 3
}
DEF TABLE Solid {
  translation 0 0 0.4
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.6 0.4 0.2
        roughness 0.8
      }
      geometry Box {
        size 0.8 0.6 0.05
      }
    }
  ]
  name "table"
}
DEF RED_BOX Solid {
  translation 0.15 0.1 0.475
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.1 0.1
        roughness 0.5
      }
      geometry Box {
        size 0.1 0.1 0.1
      }
    }
  ]
  name "red_box"
}
DEF BLUE_SPHERE Solid {
  translation -0.15 0.05 0.475
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.1 0.1 0.8
        roughness 0.3
      }
      geometry Sphere {
        radius 0.05
      }
    }
  ]
  name "blue_sphere"
}
DEF GREEN_CYLINDER Solid {
  translation 0.0 -0.15 0.475
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.1 0.7 0.1
        roughness 0.4
      }
      geometry Cylinder {
        height 0.12
        radius 0.04
      }
    }
  ]
  name "green_cylinder"
}
EOF

chown ga:ga /home/ga/webots_projects/tabletop_scene.wbt

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Clean up any potential previous output
rm -f /home/ga/Desktop/physics_configured.wbt

# Launch Webots with the scene
echo "Launching Webots..."
launch_webots_with_world /home/ga/webots_projects/tabletop_scene.wbt

# Wait for Webots UI, focus and maximize
sleep 5
focus_webots

# Dismiss any Webots popups/dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="