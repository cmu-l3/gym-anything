#!/bin/bash
echo "=== Setting up configure_balancing_robot_sim2real task ==="

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
mkdir -p /home/ga/webots_projects
chown ga:ga /home/ga/webots_projects

USER_WORLD="/home/ga/webots_projects/balancing_robot_uncalibrated.wbt"

# Generate the base world file directly to ensure it perfectly matches the scenario
# without relying on external static data files.
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 16
  title "Uncalibrated Balancing Robot"
}
Viewpoint {
  orientation -0.25 0.95 0.15 1.0
  position 3.0 2.0 2.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
DEF SEGWAY_ROBOT Robot {
  translation 0 0 0.1
  children [
    Shape {
      geometry Box {
        size 0.2 0.2 0.8
      }
    }
    DEF pitch_gyro Gyro {
      name "pitch_gyro"
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
        anchor 0 0 -0.4
      }
      device [
        PositionSensor {
          name "left_encoder"
        }
        RotationalMotor {
          name "left_motor"
        }
      ]
      endPoint Solid {
        translation 0 0.25 -0.4
        children [
          Shape {
            geometry Cylinder {
              height 0.05
              radius 0.1
            }
          }
        ]
        physics Physics {
          mass 1.0
        }
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
        anchor 0 0 -0.4
      }
      device [
        PositionSensor {
          name "right_encoder"
        }
        RotationalMotor {
          name "right_motor"
        }
      ]
      endPoint Solid {
        translation 0 -0.25 -0.4
        children [
          Shape {
            geometry Cylinder {
              height 0.05
              radius 0.1
            }
          }
        ]
        physics Physics {
          mass 1.0
        }
      }
    }
  ]
  name "balancing_robot"
  physics Physics {
    mass 10.0
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/segway_calibrated.wbt

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
echo "Agent should:"
echo "  1. Change SEGWAY_ROBOT mass to 45.5"
echo "  2. Change SEGWAY_ROBOT centerOfMass to 0 0 0.15"
echo "  3. Change left_encoder and right_encoder resolution to 0.001534"
echo "  4. Change pitch_gyro noise to 0.005"
echo "  5. Save to /home/ga/Desktop/segway_calibrated.wbt"