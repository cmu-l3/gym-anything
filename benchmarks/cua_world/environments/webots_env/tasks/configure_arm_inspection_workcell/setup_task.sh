#!/bin/bash
echo "=== Setting up configure_arm_inspection_workcell task ==="

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

# Record timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Create working directories
mkdir -p /home/ga/webots_projects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/webots_projects
chown ga:ga /home/ga/Desktop

# Remove any previous output file to prevent gaming
rm -f /home/ga/Desktop/inspection_workcell.wbt

USER_WORLD="/home/ga/webots_projects/inspection_workcell_draft.wbt"

# Generate the draft starting world procedurally
# This accurately models a misconfigured placeholder world requiring fixes
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 64
}
Viewpoint {
  orientation -0.2 0.9 0.35 1.1
  position 4.5 3.0 4.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
DEF CONVEYOR Solid {
  translation 1.5 0 0.4
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.5 0.5 0.5
        roughness 0.8
      }
      geometry Box {
        size 2 0.5 0.1
      }
    }
  ]
  name "CONVEYOR"
}
DEF INSPECTION_ARM Robot {
  translation 0 0 0
  children [
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
      }
      device [
        DEF shoulder_motor RotationalMotor {
          name "shoulder"
          maxVelocity 6.28
        }
      ]
      endPoint Solid {
        translation 0 0 0.5
        children [
          Shape {
            appearance PBRAppearance {
              baseColor 0.2 0.4 0.8
            }
            geometry Cylinder {
              height 1
              radius 0.1
            }
          }
          DEF tool_slot Solid {
            translation 0 0 0.5
            children [
              DEF inspection_camera Camera {
                width 64
                height 64
                fieldOfView 1.5708
              }
            ]
          }
        ]
      }
    }
  ]
  name "INSPECTION_ARM"
  controller "<none>"
}
EOF

chown ga:ga "$USER_WORLD"

# Launch Webots with the drafted world
echo "Launching Webots with the inspection workcell draft..."
launch_webots_with_world "$USER_WORLD"

sleep 6

# Focus and maximize the window
focus_webots

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Draft world loaded: $USER_WORLD"
echo "Agent must edit parameters and Save As: /home/ga/Desktop/inspection_workcell.wbt"