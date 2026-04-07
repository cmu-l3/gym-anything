#!/bin/bash
echo "=== Setting up configure_ptz_camera_inspection task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

# Create the starting world file programmatically to ensure a known clean state
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/pipeline_crawler.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.1
  position 2 1.5 2
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
DEF INSPECTION_CRAWLER Robot {
  translation 0 0.05 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
      }
      geometry Box {
        size 0.3 0.1 0.4
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
        anchor 0 0.1 0
      }
      device [
        RotationalMotor {
          name "pan_motor"
          minPosition 0
          maxPosition 0
        }
      ]
      endPoint Solid {
        translation 0 0.1 0
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.2 0.2 0.2
            }
            geometry Cylinder {
              height 0.05
              radius 0.05
            }
          }
          HingeJoint {
            jointParameters HingeJointParameters {
              axis 1 0 0
              anchor 0 0.05 0
            }
            device [
              RotationalMotor {
                name "tilt_motor"
                minPosition 0
                maxPosition 0
              }
            ]
            endPoint Solid {
              translation 0 0.05 0
              children [
                DEF ptz_camera Camera {
                  translation 0 0 0.05
                  name "ptz_camera"
                  fieldOfView 1.047
                  width 640
                  height 480
                }
                Shape {
                  appearance PBRAppearance {
                    baseColor 0.1 0.1 0.1
                  }
                  geometry Box {
                    size 0.08 0.08 0.12
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
  name "crawler"
  boundingObject Box {
    size 0.3 0.1 0.4
  }
  physics Physics {
    mass 5
  }
}
EOF
chown ga:ga "$USER_WORLD"

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/ptz_crawler_configured.wbt

# Launch Webots with the crawler world
echo "Launching Webots with pipeline crawler world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent should modify pan/tilt limits and add Zoom/Focus nodes to the camera."