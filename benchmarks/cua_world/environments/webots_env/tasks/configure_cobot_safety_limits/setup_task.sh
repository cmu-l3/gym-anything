#!/bin/bash
# Setup script for configure_cobot_safety_limits task
# Generates a realistic cobot workstation world with incorrect safety parameters,
# and loads it in Webots for the agent to fix.

echo "=== Setting up configure_cobot_safety_limits task ==="

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
USER_WORLD="/home/ga/webots_projects/cobot_workstation.wbt"
mkdir -p /home/ga/webots_projects

# Generate the Cobot Webots world file programmatically
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.4
  position 3.5 2.5 3.0
}
TexturedBackground {}
TexturedBackgroundLight {}
RectangleArena {
  floorSize 5 5
}
DEF COBOT Robot {
  translation 0 0.5 0
  children [
    DEF BASE_JOINT HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
      }
      device [
        RotationalMotor {
          name "base_motor"
          maxVelocity 10.0
        }
      ]
      endPoint Solid {
        translation 0 0.2 0
        children [
          Shape {
            appearance PBRAppearance { baseColor 0.8 0.2 0.2 roughness 0.5 metalness 0.5 }
            geometry Cylinder { height 0.4 radius 0.1 }
          }
          DEF SHOULDER_JOINT HingeJoint {
            jointParameters HingeJointParameters {
              axis 1 0 0
              anchor 0 0.2 0
            }
            device [
              RotationalMotor {
                name "shoulder_motor"
                maxVelocity 10.0
              }
            ]
            endPoint Solid {
              translation 0 0.4 0
              children [
                Shape {
                  appearance PBRAppearance { baseColor 0.2 0.2 0.8 roughness 0.5 metalness 0.5 }
                  geometry Box { size 0.1 0.6 0.1 }
                }
              ]
              physics Physics { density -1 mass 2.0 }
            }
          }
        ]
        physics Physics { density -1 mass 5.0 }
      }
    }
  ]
  name "cobot_arm"
  controller "<none>"
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/safe_cobot.wbt

# Launch Webots with the scenario world
echo "Launching Webots with cobot scenario..."
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
echo "Agent should find BASE_JOINT and SHOULDER_JOINT and configure their minStop, maxStop, and maxVelocity."
echo "Save to /home/ga/Desktop/safe_cobot.wbt"