#!/bin/bash
# Setup script for configure_underactuated_gripper task

echo "=== Setting up configure_underactuated_gripper task ==="

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

# Generate the initial Webots world file for the task
USER_WORLD="/home/ga/webots_projects/adaptive_gripper_test.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo { basicTimeStep 16 }
Viewpoint { position 0.3 0.2 0.3 orientation -0.2 0.9 0.3 1.0 }
TexturedBackground {}
TexturedBackgroundLight {}
DEF ADAPTIVE_FINGER Robot {
  translation 0 0 0
  children [
    HingeJoint {
      jointParameters HingeJointParameters { axis 0 0 1 }
      device [ RotationalMotor { name "motor_base" maxTorque 10 multiplier 1 } ]
      endPoint Solid {
        translation 0.1 0 0
        children [
          Shape { geometry Box { size 0.1 0.02 0.02 } }
          HingeJoint {
            jointParameters HingeJointParameters { axis 0 0 1 }
            device [ RotationalMotor { name "motor_mid" maxTorque 10 multiplier 1 } ]
            endPoint Solid {
              translation 0.1 0 0
              children [
                Shape { geometry Box { size 0.1 0.02 0.02 } }
                HingeJoint {
                  jointParameters HingeJointParameters { axis 0 0 1 }
                  device [ RotationalMotor { name "motor_tip" maxTorque 10 multiplier 1 } ]
                  endPoint Solid {
                    translation 0.05 0 0
                    children [ Shape { geometry Box { size 0.05 0.02 0.02 } } ]
                    boundingObject Box { size 0.05 0.02 0.02 }
                    physics Physics {}
                  }
                }
              ]
              boundingObject Box { size 0.1 0.02 0.02 }
              physics Physics {}
            }
          }
        ]
        boundingObject Box { size 0.1 0.02 0.02 }
        physics Physics {}
      }
    }
  ]
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/coupled_finger.wbt

# Launch Webots with the generated world
echo "Launching Webots with adaptive gripper test world..."
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