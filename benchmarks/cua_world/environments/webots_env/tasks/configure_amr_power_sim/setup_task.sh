#!/bin/bash
# Setup script for configure_amr_power_sim task
# Creates a minimal AMR Webots world and launches it.

echo "=== Setting up configure_amr_power_sim task ==="

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

# Construct the starting world with unconfigured power settings
USER_WORLD="/home/ga/webots_projects/warehouse_amr_setup.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.2
  position 1.5 1.5 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
DEF DELIVERY_AMR Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.3 0.1
        roughness 0.5
      }
      geometry Box {
        size 0.4 0.2 0.6
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        anchor 0.25 0 0
      }
      device [
        RotationalMotor {
          name "left_wheel_motor"
          consumptionFactor 10.0
        }
      ]
      endPoint Solid {
        translation 0.25 0 0
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.2 0.2 0.2
            }
            geometry Cylinder {
              height 0.05
              radius 0.1
            }
          }
        ]
        physics Physics {
          density -1
          mass 1
        }
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        anchor -0.25 0 0
      }
      device [
        RotationalMotor {
          name "right_wheel_motor"
          consumptionFactor 10.0
        }
      ]
      endPoint Solid {
        translation -0.25 0 0
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.2 0.2 0.2
            }
            geometry Cylinder {
              height 0.05
              radius 0.1
            }
          }
        ]
        physics Physics {
          density -1
          mass 1
        }
      }
    }
  ]
  name "DELIVERY_AMR"
  battery []
  cpuConsumption 0.0
  controller "<generic>"
  physics Physics {
    density -1
    mass 20
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/amr_power_sim.wbt

# Launch Webots with the scenario world
echo "Launching Webots with AMR power simulation world..."
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
echo "  1. Add [1800000, 1800000, 2000] to DELIVERY_AMR battery"
echo "  2. Set DELIVERY_AMR cpuConsumption to 15.0"
echo "  3. Set consumptionFactor to 3.5 for both left_wheel_motor and right_wheel_motor"
echo "  4. Save to /home/ga/Desktop/amr_power_sim.wbt"