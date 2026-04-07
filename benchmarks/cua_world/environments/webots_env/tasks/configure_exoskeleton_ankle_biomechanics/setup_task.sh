#!/bin/bash
echo "=== Setting up configure_exoskeleton_ankle_biomechanics task ==="

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

# Create the starting world file with zeroed/default physics parameters
USER_WORLD="/home/ga/webots_projects/exoskeleton_gait_test.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.16 -0.96 -0.19 1.15
  position -2.5 1.5 1.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 3 3
}
DEF EXO_LEG Robot {
  translation 0 0 1.2
  children [
    DEF KNEE_JOINT HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
      }
      device [
        PositionSensor {
          name "knee_sensor"
        }
      ]
      endPoint Solid {
        translation 0 0 -0.5
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.8 0.2 0.2
            }
            geometry Cylinder {
              height 0.5
              radius 0.05
            }
          }
          DEF ANKLE_JOINT HingeJoint {
            jointParameters HingeJointParameters {
              axis 0 1 0
            }
            device [
              DEF ANKLE_SENSOR PositionSensor {
                name "ankle_sensor"
                resolution -1
              }
            ]
            endPoint Solid {
              translation 0 0 -0.4
              children [
                Shape {
                  appearance PBRAppearance {
                    baseColor 0.2 0.2 0.8
                  }
                  geometry Box {
                    size 0.3 0.1 0.1
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
  name "exo_leg"
  boundingObject Cylinder {
    height 0.6
    radius 0.06
  }
  physics Physics {
    density -1
    mass 5
  }
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/exoskeleton_biomechanics.wbt

# Launch Webots with the exoskeleton scenario world
echo "Launching Webots with exoskeleton scenario world..."
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