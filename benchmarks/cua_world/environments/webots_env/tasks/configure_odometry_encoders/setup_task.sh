#!/bin/bash
echo "=== Setting up configure_odometry_encoders task ==="

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

# Create the task's custom world file directly
USER_WORLD="/home/ga/webots_projects/hospital_scenario.wbt"
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
  orientation -0.2 0.9 0.3 1.2
  position 2.0 1.5 2.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
DEF HOSPITAL_ROBOT Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
        metalness 0
      }
      geometry Box {
        size 0.4 0.2 0.6
      }
    }
    DEF left_wheel_joint HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        anchor 0.25 0 0
      }
      device [
        RotationalMotor {
          name "left_motor"
        }
      ]
      endPoint Solid {
        translation 0.25 0 0
        rotation 0 0 1 1.5708
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.1 0.1 0.1
              roughness 1
              metalness 0
            }
            geometry Cylinder {
              height 0.05
              radius 0.1
            }
          }
        ]
        boundingObject Cylinder {
          height 0.05
          radius 0.1
        }
        physics Physics {
        }
      }
    }
    DEF right_wheel_joint HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        anchor -0.25 0 0
      }
      device [
        RotationalMotor {
          name "right_motor"
        }
      ]
      endPoint Solid {
        translation -0.25 0 0
        rotation 0 0 1 1.5708
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.1 0.1 0.1
              roughness 1
              metalness 0
            }
            geometry Cylinder {
              height 0.05
              radius 0.1
            }
          }
        ]
        boundingObject Cylinder {
          height 0.05
          radius 0.1
        }
        physics Physics {
        }
      }
    }
  ]
  boundingObject Box {
    size 0.4 0.2 0.6
  }
  physics Physics {
    mass 20
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/hospital_robot_odometry.wbt

# Launch Webots with the scenario world
echo "Launching Webots with hospital scenario world..."
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