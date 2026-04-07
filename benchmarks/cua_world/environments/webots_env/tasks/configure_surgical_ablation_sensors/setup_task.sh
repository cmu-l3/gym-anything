#!/bin/bash
echo "=== Setting up configure_surgical_ablation_sensors task ==="

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

# Create the task's custom world file in a writable location
USER_WORLD="/home/ga/webots_projects/surgical_ablation_sim.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  title "Surgical Ablation Simulation"
}
Viewpoint {
  orientation -0.25 0.9 0.3 1.2
  position 0.8 1.5 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 2 2
}
DEF TISSUE_BLOCK Solid {
  translation 0 0.05 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.5 0.5
        roughness 0.8
        metalness 0
      }
      geometry Box {
        size 0.4 0.1 0.4
      }
    }
  ]
  name "tissue_block"
  boundingObject Box {
    size 0.4 0.1 0.4
  }
}
DEF SURGICAL_ARM Robot {
  translation 0 0.1 0
  children [
    Solid {
      translation 0 0.5 0
      children [
        DEF ABLATION_TOOL Solid {
          translation 0 0.2 0
          children [
            Shape {
              appearance PBRAppearance {
                baseColor 0.7 0.7 0.7
                metalness 0.9
                roughness 0.2
              }
              geometry Cylinder {
                height 0.1
                radius 0.01
              }
            }
          ]
          name "ablation_tool"
          boundingObject Cylinder {
            height 0.1
            radius 0.01
          }
          physics Physics {
            mass 0.5
          }
        }
      ]
      name "arm_link"
    }
  ]
  name "surgical_robot"
  controller "void"
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/validated_surgical_sim.wbt

# Launch Webots with the scenario world
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
echo "World loaded: $USER_WORLD"
echo "Agent must attach Pen and TouchSensor to ABLATION_TOOL and save to Desktop."