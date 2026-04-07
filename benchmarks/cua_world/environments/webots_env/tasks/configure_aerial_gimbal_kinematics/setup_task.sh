#!/bin/bash
echo "=== Setting up configure_aerial_gimbal_kinematics task ==="

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

# Create the starting world programmatically
USER_WORLD="/home/ga/webots_projects/aerial_gimbal.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.9 0.4 1.5
  position 1.5 1.5 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
DEF GIMBAL_PAYLOAD Robot {
  translation 0 1 0
  children [
    HingeJoint {
      device [
        RotationalMotor {
          name "pan_motor"
          controlPID 10 0 0
          minPosition 0
          maxPosition 0
        }
      ]
      endPoint Solid {
        children [
          Shape {
            geometry Cylinder {
              height 0.1
              radius 0.05
            }
          }
          HingeJoint {
            device [
              RotationalMotor {
                name "tilt_motor"
                controlPID 10 0 0
                minPosition 0
                maxPosition 0
              }
            ]
            endPoint Solid {
              translation 0 -0.1 0
              children [
                Shape {
                  geometry Box {
                    size 0.05 0.1 0.05
                  }
                }
                HingeJoint {
                  device [
                    RotationalMotor {
                      name "roll_motor"
                      controlPID 10 0 0
                      minPosition 0
                      maxPosition 0
                    }
                  ]
                  endPoint Solid {
                    translation 0 -0.1 0
                    name "camera_body"
                    children [
                      Shape {
                        geometry Box {
                          size 0.1 0.1 0.1
                        }
                      }
                      Camera {
                        name "gimbal_camera"
                        translation 0 0 -0.05
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
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
rm -f /home/ga/Desktop/stabilized_gimbal.wbt

# Launch Webots with the payload world
echo "Launching Webots with aerial gimbal scenario..."
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
echo "Agent should find the 3 nested gimbal motors and configure their limits and PID."