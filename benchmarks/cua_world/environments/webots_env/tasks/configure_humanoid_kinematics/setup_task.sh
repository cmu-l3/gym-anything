#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_humanoid_kinematics task ==="

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

# Set up project directory
PROJECT_DIR="/home/ga/webots_projects/biped_project"
WORLD_DIR="$PROJECT_DIR/worlds"
mkdir -p "$WORLD_DIR"

USER_WORLD="$WORLD_DIR/biped_setup.wbt"

# Generate the starting world file with misconfigured / default physics
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  basicTimeStep 32
  title "Biped Setup"
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.0
  position -2.5 1.5 2.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
DEF BIPED_ROBOT Robot {
  translation 0 0.8 0
  children [
    DEF TORSO Solid {
      children [
        Shape {
          appearance PBRAppearance {
            baseColor 0.8 0.2 0.2
            roughness 0.5
          }
          geometry Box {
            size 0.3 0.4 0.2
          }
        }
      ]
      boundingObject Box {
        size 0.3 0.4 0.2
      }
      physics Physics {
        mass 10
      }
    }
    DEF LEFT_HIP HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        anchor 0.1 0.6 0
      }
      endPoint Solid {
        translation 0.1 0.4 0
        children [
          DEF LEFT_KNEE HingeJoint {
            jointParameters HingeJointParameters {
              axis 1 0 0
              anchor 0.1 0.2 0
            }
            endPoint Solid {
              translation 0.1 0 0
              children [
                Shape {
                  appearance PBRAppearance {
                    baseColor 0.2 0.2 0.8
                  }
                  geometry Cylinder {
                    height 0.4
                    radius 0.05
                  }
                }
              ]
              boundingObject Cylinder {
                height 0.4
                radius 0.05
              }
              physics Physics {
                mass 2
              }
            }
          }
        ]
        boundingObject Cylinder {
          height 0.4
          radius 0.05
        }
        physics Physics {
          mass 2
        }
      }
    }
    DEF RIGHT_HIP HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        anchor -0.1 0.6 0
      }
      endPoint Solid {
        translation -0.1 0.4 0
        children [
          DEF RIGHT_KNEE HingeJoint {
            jointParameters HingeJointParameters {
              axis 1 0 0
              anchor -0.1 0.2 0
            }
            endPoint Solid {
              translation -0.1 0 0
              children [
                Shape {
                  appearance PBRAppearance {
                    baseColor 0.2 0.2 0.8
                  }
                  geometry Cylinder {
                    height 0.4
                    radius 0.05
                  }
                }
              ]
              boundingObject Cylinder {
                height 0.4
                radius 0.05
              }
              physics Physics {
                mass 2
              }
            }
          }
        ]
        boundingObject Cylinder {
          height 0.4
          radius 0.05
        }
        physics Physics {
          mass 2
        }
      }
    }
  ]
  name "biped_humanoid"
  boundingObject Box {
    size 0.3 0.4 0.2
  }
  physics Physics {
    mass 10
  }
}
EOF

chown -R ga:ga "$PROJECT_DIR"

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create Desktop directory
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/biped_kinematics.wbt

# Launch Webots with the base scenario world
echo "Launching Webots with biped setup world..."
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
echo "Starting conditions:"
echo " - basicTimeStep is 32"
echo " - selfCollision is FALSE (default)"
echo " - LEFT_KNEE and RIGHT_KNEE lack minStop, maxStop, and dampingConstant"