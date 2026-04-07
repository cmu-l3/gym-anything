#!/bin/bash
# Setup script for configure_automatic_door_kinematics task

echo "=== Setting up configure_automatic_door_kinematics task ==="

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

# Create the task's custom world file
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/hospital_corridor.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.96 0.22 1.8
  position -3.4 2.8 3.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 10 10
}
DEF AUTO_DOOR Robot {
  translation 0 0 0
  children [
    DEF DOOR_SENSOR DistanceSensor {
      translation 0 1 0
      name "door_sensor"
      maxRange 0.5
    }
    SliderJoint {
      jointParameters DEF DOOR_PARAMS JointParameters {
        axis 1 0 0
        maxStop 0.5
      }
      device [
        DEF DOOR_MOTOR LinearMotor {
          name "door_motor"
          maxVelocity 0.1
          maxForce 1.0
        }
      ]
      endPoint Solid {
        translation 0 1 0
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.8 0.8 0.8
            }
            geometry Box {
              size 1 2 0.1
            }
          }
        ]
        boundingObject Box {
          size 1 2 0.1
        }
        physics Physics {
          mass 50
        }
      }
    }
  ]
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/hospital_door_fixed.wbt

# Launch Webots
echo "Launching Webots with hospital corridor world..."
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
echo "Agent should:"
echo "  1. Change DOOR_SENSOR maxRange to 4.0"
echo "  2. Change DOOR_PARAMS maxStop to 1.5"
echo "  3. Change DOOR_MOTOR maxVelocity to 0.8 and maxForce to 150.0"
echo "  4. Save to /home/ga/Desktop/hospital_door_fixed.wbt"