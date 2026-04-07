#!/bin/bash
# Setup script for configure_slam_sensor_noise task

echo "=== Setting up configure_slam_sensor_noise task ==="

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

# Create the starting world with perfect sensors
USER_WORLD="/home/ga/webots_projects/perfect_odometry_room.wbt"
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
  orientation -0.57735 0.57735 0.57735 2.0944
  position 0 0 10
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
DEF CLEANING_ROBOT Robot {
  translation 0 0.05 0
  children [
    Shape {
      geometry Cylinder {
        height 0.1
        radius 0.15
      }
    }
    DEF LEFT_WHEEL HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
        anchor -0.15 0 0
      }
      device [
        PositionSensor {
          name "left_encoder"
        }
      ]
    }
    DEF RIGHT_WHEEL HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
        anchor 0.15 0 0
      }
      device [
        PositionSensor {
          name "right_encoder"
        }
      ]
    }
    DistanceSensor {
      translation 0.15 0 0
      name "ir_front"
    }
    DistanceSensor {
      translation 0 0 0.15
      rotation 0 1 0 1.5708
      name "ir_left"
    }
    DistanceSensor {
      translation 0 0 -0.15
      rotation 0 1 0 -1.5708
      name "ir_right"
    }
  ]
  name "cleaning_robot"
  boundingObject Cylinder {
    height 0.1
    radius 0.15
  }
  physics Physics {
    density -1
    mass 5
  }
  controller "void"
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure output directory exists and is clean
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/noisy_slam_test.wbt

# Launch Webots with the scenario
echo "Launching Webots..."
launch_webots_with_world "$USER_WORLD"
sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for VLM context/evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"