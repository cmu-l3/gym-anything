#!/bin/bash
# Setup script for configure_arm_motor_params task
# Generates a realistic Webots world with a 3-DOF robotic arm containing
# incorrectly configured motor parameters for the agent to fix.

echo "=== Setting up configure_arm_motor_params task ==="

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

# Create the task's world file
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/palletizing_arm.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.5
  position 3.5 2.5 3.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 4 4
}
DEF PALLETIZING_ARM Robot {
  translation 0 0 0
  children [
    DEF BASE_SHAPE Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.2 0.2
        roughness 1
        metalness 0
      }
      geometry Cylinder {
        height 0.2
        radius 0.2
      }
    }
    DEF SHOULDER_JOINT HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 0 1
        anchor 0 0 0.2
      }
      device [
        RotationalMotor {
          name "shoulder_motor"
          maxVelocity 10.0
          maxTorque 150.0
        }
      ]
      endPoint DEF UPPER_ARM Solid {
        translation 0 0 0.2
        children [
          DEF UPPER_ARM_SHAPE Shape {
            appearance PBRAppearance {
              baseColor 0.8 0.4 0.1
              roughness 0.5
              metalness 0
            }
            geometry Box {
              size 0.1 0.1 1.0
            }
          }
          DEF ELBOW_JOINT HingeJoint {
            jointParameters HingeJointParameters {
              axis 0 1 0
              anchor 0 0 0.5
            }
            device [
              RotationalMotor {
                name "elbow_motor"
                maxVelocity 0.5
                maxTorque 5.0
              }
            ]
            endPoint DEF FOREARM Solid {
              translation 0 0 0.5
              children [
                DEF FOREARM_SHAPE Shape {
                  appearance PBRAppearance {
                    baseColor 0.8 0.4 0.1
                    roughness 0.5
                    metalness 0
                  }
                  geometry Box {
                    size 0.1 0.1 0.8
                  }
                }
                DEF WRIST_JOINT HingeJoint {
                  jointParameters HingeJointParameters {
                    axis 0 0 1
                    anchor 0 0 0.4
                  }
                  device [
                    RotationalMotor {
                      name "wrist_motor"
                      maxVelocity 3.14
                      maxTorque 28.0
                      minPosition -1.0
                      maxPosition 1.0
                    }
                  ]
                  endPoint DEF WRIST Solid {
                    translation 0 0 0.4
                    children [
                      DEF WRIST_SHAPE Shape {
                        appearance PBRAppearance {
                          baseColor 0.2 0.2 0.2
                          roughness 1
                          metalness 0
                        }
                        geometry Box {
                          size 0.05 0.05 0.2
                        }
                      }
                    ]
                    boundingObject USE WRIST_SHAPE
                    physics Physics {
                      mass 1.0
                    }
                  }
                }
              ]
              boundingObject USE FOREARM_SHAPE
              physics Physics {
                mass 5.0
              }
            }
          }
        ]
        boundingObject USE UPPER_ARM_SHAPE
        physics Physics {
          mass 10.0
        }
      }
    }
  ]
  boundingObject USE BASE_SHAPE
  physics Physics {
    mass 20.0
  }
  controller "void"
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure output directory exists and is clean
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/palletizing_arm_configured.wbt

# Launch Webots with the generated arm scenario
echo "Launching Webots with palletizing arm world..."
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