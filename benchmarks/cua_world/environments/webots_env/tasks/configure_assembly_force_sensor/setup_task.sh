#!/bin/bash
echo "=== Setting up configure_assembly_force_sensor task ==="

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

USER_WORLD="/home/ga/webots_projects/assembly_cell.wbt"
mkdir -p /home/ga/webots_projects

# Create a baseline world
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.2 0.9 0.3 1.2
  position 1.5 1.5 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
Floor {
  size 5 5
}
DEF ASSEMBLY_PRESS Robot {
  translation 0 0.5 0
  children [
    SliderJoint {
      jointParameters JointParameters {
        axis 0 -1 0
        dampingConstant 0
      }
      device [
        LinearMotor {
          name "press_motor"
          maxForce 10
        }
      ]
      endPoint Solid {
        translation 0 -0.2 0
        children [
          DEF load_cell TouchSensor {
            translation 0 -0.1 0
            children [
              Shape {
                appearance PBRAppearance {
                  baseColor 0.8 0.2 0.2
                }
                geometry Cylinder {
                  height 0.05
                  radius 0.05
                }
              }
            ]
            name "load_cell"
            type "bumper"
            resolution -1
          }
        ]
        boundingObject Cylinder {
          height 0.05
          radius 0.05
        }
        physics Physics {
          mass 1
        }
      }
    }
  ]
  name "ASSEMBLY_PRESS"
  boundingObject Box {
    size 0.2 0.5 0.2
  }
  physics Physics {
    mass 50
  }
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/assembly_press_configured.wbt

# Launch Webots
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