#!/bin/bash
echo "=== Setting up configure_cnc_marker_twin task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming validation
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/webots_projects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/webots_projects /home/ga/Desktop

WORLD_FILE="/home/ga/webots_projects/cnc_marker.wbt"

# Programmatically create the initial world with dangerous limits and wrong pen
cat > "$WORLD_FILE" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.5773 0.5773 0.5773 2.0944
  position 1 1 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
DEF CNC_PLOTTER Robot {
  translation 0 0 0.1
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
      }
      geometry Box {
        size 0.5 0.5 0.1
      }
    }
    SliderJoint {
      jointParameters DEF X_LIMITS JointParameters {
        axis 1 0 0
        minStop -1.0
        maxStop 1.0
      }
      endPoint Solid {
        translation 0 0 0.1
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.2 0.5 0.8
            }
            geometry Box {
              size 0.1 0.4 0.1
            }
          }
          SliderJoint {
            jointParameters DEF Y_LIMITS JointParameters {
              axis 0 1 0
              minStop -1.0
              maxStop 1.0
            }
            endPoint Solid {
              translation 0 0 0.1
              children [
                Shape {
                  appearance PBRAppearance {
                    baseColor 0.8 0.2 0.2
                  }
                  geometry Cylinder {
                    height 0.2
                    radius 0.02
                  }
                }
                DEF MARKING_PEN Pen {
                  translation 0 0 -0.1
                  write FALSE
                  inkColor 0 0 0
                  leadSize 0.01
                }
              ]
            }
          }
        ]
      }
    }
  ]
}
EOF

chown ga:ga "$WORLD_FILE"
rm -f /home/ga/Desktop/cnc_digital_twin.wbt

# Launch Webots with the created world
echo "Launching Webots..."
launch_webots_with_world "$WORLD_FILE"

# Wait for UI to initialize
sleep 5

# Focus and maximize window for the agent
focus_webots
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="