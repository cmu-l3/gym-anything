#!/bin/bash
set -euo pipefail

echo "=== Setting up AS/RS Crane Linear Kinematics task ==="

export DISPLAY=${DISPLAY:-:1}
export LIBGL_ALWAYS_SOFTWARE=1

# Create webots projects directory
mkdir -p /home/ga/webots_projects/asrs_project/worlds
chown -R ga:ga /home/ga/webots_projects

USER_WORLD="/home/ga/webots_projects/asrs_project/worlds/asrs_warehouse.wbt"

# Generate the initial world file with nested joints (unbounded limits/speeds)
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  coordinateSystem "ENU"
}
Viewpoint {
  orientation -0.16 0.95 0.25 1.15
  position -12 10 18
}
TexturedBackground {
}
TexturedBackgroundLight {
}
Solid {
  translation 12.5 4.25 -2
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.3 0.8
        roughness 0.5
      }
      geometry Box {
        size 26 8.5 2
      }
    }
  ]
  name "RACK_SYSTEM"
  boundingObject Box {
    size 26 8.5 2
  }
}
DEF ASRS_CRANE Robot {
  translation 0 0 0
  children [
    DEF X_AXIS_JOINT SliderJoint {
      jointParameters JointParameters {
        axis 1 0 0
        minStop 0
        maxStop 0
      }
      device [
        LinearMotor {
          name "x_motor"
          maxVelocity 10
        }
      ]
      endPoint Solid {
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.8 0.2 0.2
            }
            geometry Box {
              size 1 0.5 1
            }
          }
          DEF Y_AXIS_JOINT SliderJoint {
            jointParameters JointParameters {
              axis 0 1 0
              minStop 0
              maxStop 0
            }
            device [
              LinearMotor {
                name "y_motor"
                maxVelocity 10
              }
            ]
            endPoint Solid {
              children [
                Shape {
                  appearance PBRAppearance {
                    baseColor 0.8 0.8 0.2
                  }
                  geometry Box {
                    size 0.8 1 0.8
                  }
                }
                DEF Z_AXIS_JOINT SliderJoint {
                  jointParameters JointParameters {
                    axis 0 0 1
                    minStop 0
                    maxStop 0
                  }
                  device [
                    LinearMotor {
                      name "z_motor"
                      maxVelocity 10
                    }
                  ]
                  endPoint Solid {
                    children [
                      Shape {
                        appearance PBRAppearance {
                          baseColor 0.2 0.8 0.2
                        }
                        geometry Box {
                          size 0.2 0.1 2.5
                        }
                      }
                    ]
                    name "FORKS"
                  }
                }
              ]
              name "CARRIAGE"
            }
          }
        ]
        name "MAST_BASE"
      }
    }
  ]
  name "ASRS_CRANE"
}
EOF
chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Clear out any previous result files
rm -f /home/ga/Desktop/asrs_configured.wbt
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Kill existing Webots
pkill -f webots 2>/dev/null || true
sleep 2

# Launch Webots
echo "Launching Webots..."
su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 /usr/local/webots/webots --batch --mode=pause \"$USER_WORLD\" > /tmp/webots.log 2>&1 &"

# Wait for Webots window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "webots"; then
        break
    fi
    sleep 1
done
sleep 3

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "webots" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="