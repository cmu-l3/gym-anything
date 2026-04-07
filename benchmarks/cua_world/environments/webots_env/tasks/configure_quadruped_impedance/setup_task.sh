#!/bin/bash
# Setup script for configure_quadruped_impedance task

echo "=== Setting up configure_quadruped_impedance task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

# Generate the world file with the quadruped
USER_WORLD="/home/ga/webots_projects/quadruped_test.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 32
}
Viewpoint {
  orientation -0.2 0.9 0.3 1.1
  position 1.5 1.5 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
}
DEF CUSTOM_QUADRUPED Robot {
  translation 0 0.5 0
  children [
    Shape {
      geometry Box {
        size 0.5 0.2 0.3
      }
    }
    DEF FL_HIP HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
      }
      device [
        RotationalMotor {
          name "fl_hip_motor"
        }
      ]
      endPoint Solid {
        translation 0.25 -0.1 0.15
        children [
          DEF FL_KNEE HingeJoint {
            jointParameters HingeJointParameters {
              axis 0 1 0
            }
            device [
              RotationalMotor {
                name "fl_knee_motor"
              }
            ]
            endPoint Solid {
              translation 0 -0.2 0
            }
          }
        ]
      }
    }
    DEF FR_HIP HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
      }
      device [
        RotationalMotor {
          name "fr_hip_motor"
        }
      ]
      endPoint Solid {
        translation 0.25 -0.1 -0.15
        children [
          DEF FR_KNEE HingeJoint {
            jointParameters HingeJointParameters {
              axis 0 1 0
            }
            device [
              RotationalMotor {
                name "fr_knee_motor"
              }
            ]
            endPoint Solid {
              translation 0 -0.2 0
            }
          }
        ]
      }
    }
    DEF RL_HIP HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
      }
      device [
        RotationalMotor {
          name "rl_hip_motor"
        }
      ]
      endPoint Solid {
        translation -0.25 -0.1 0.15
        children [
          DEF RL_KNEE HingeJoint {
            jointParameters HingeJointParameters {
              axis 0 1 0
            }
            device [
              RotationalMotor {
                name "rl_knee_motor"
              }
            ]
            endPoint Solid {
              translation 0 -0.2 0
            }
          }
        ]
      }
    }
    DEF RR_HIP HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
      }
      device [
        RotationalMotor {
          name "rr_hip_motor"
        }
      ]
      endPoint Solid {
        translation -0.25 -0.1 -0.15
        children [
          DEF RR_KNEE HingeJoint {
            jointParameters HingeJointParameters {
              axis 0 1 0
            }
            device [
              RotationalMotor {
                name "rr_knee_motor"
              }
            ]
            endPoint Solid {
              translation 0 -0.2 0
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

# Create Desktop directory
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/quadruped_impedance.wbt

# Launch Webots with the dynamic world
echo "Launching Webots with quadruped world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Agent should:"
echo "  1. Change basicTimeStep to 8"
echo "  2. Add springConstant=40.0 and dampingConstant=2.0 to FL_KNEE, FR_KNEE, RL_KNEE, RR_KNEE"
echo "  3. Not modify the HIP joints"
echo "  4. Save to /home/ga/Desktop/quadruped_impedance.wbt"