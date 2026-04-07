#!/bin/bash
echo "=== Setting up configure_imu_navigation task ==="

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

# Create the project directories
PROJECT_DIR="/home/ga/webots_projects/warehouse_nav"
mkdir -p "$PROJECT_DIR/worlds"
chown -R ga:ga /home/ga/webots_projects

# Generate the starting world file
USER_WORLD="$PROJECT_DIR/worlds/warehouse_amr.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 64
  coordinateSystem "ENU"
}
Viewpoint {
  orientation -0.27 0.9 0.3 1.2
  position 8 8 5
}
TexturedBackground {}
TexturedBackgroundLight {}
RectangleArena {
  floorSize 10 10
  floorTileSize 1 1
}
DEF WAREHOUSE_AMR Robot {
  translation 0 0 0.1
  children [
    Solid {
      children [
        Shape {
          appearance PBRAppearance {
            baseColor 0.8 0.4 0.1
            roughness 0.5
            metalness 0.2
          }
          geometry Box {
            size 0.6 0.4 0.2
          }
        }
      ]
    }
    DEF LEFT_WHEEL HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
        anchor 0 0.25 0
      }
      device [
        RotationalMotor {
          name "left_wheel_motor"
        }
      ]
      endPoint Solid {
        translation 0 0.25 0
        rotation 1 0 0 1.5708
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.2 0.2 0.2
              roughness 0.9
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
          density -1
          mass 1.5
        }
      }
    }
    DEF RIGHT_WHEEL HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
        anchor 0 -0.25 0
      }
      device [
        RotationalMotor {
          name "right_wheel_motor"
        }
      ]
      endPoint Solid {
        translation 0 -0.25 0
        rotation 1 0 0 1.5708
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.2 0.2 0.2
              roughness 0.9
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
          density -1
          mass 1.5
        }
      }
    }
    DistanceSensor {
      name "ds_front"
      translation 0.3 0 0
    }
  ]
  name "warehouse_amr"
  boundingObject Box {
    size 0.6 0.4 0.2
  }
  physics Physics {
    density -1
    mass 15.0
  }
  controller "<none>"
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/imu_configured.wbt

# Launch Webots with the AMR scenario world
echo "Launching Webots with warehouse AMR world..."
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
echo "Waiting for agent to complete task..."