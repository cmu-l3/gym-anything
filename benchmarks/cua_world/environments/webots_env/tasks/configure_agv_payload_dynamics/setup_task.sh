#!/bin/bash
echo "=== Setting up configure_agv_payload_dynamics task ==="

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

USER_WORLD="/home/ga/webots_projects/agv_logistics_cell.wbt"

# Generate the initial scenario world dynamically to ensure pure state
python3 -c "
wbt_content = '''#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.2 0.9 0.3 1.2
  position 3.0 2.5 3.0
}
TexturedBackground {}
TexturedBackgroundLight {}
RectangleArena {
  floorSize 10 10
}
DEF AGV_BASE Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance { baseColor 0.8 0.2 0.2 }
      geometry Box { size 0.8 0.2 0.5 }
    }
    DEF CUSTOM_PAYLOAD Solid {
      translation 0 0.2 0
      children [
        Shape {
          appearance PBRAppearance { baseColor 0.2 0.2 0.8 }
          geometry Box { size 0.6 0.4 0.4 }
        }
      ]
      boundingObject Box { size 0.6 0.4 0.4 }
      physics Physics {
        mass 1.0
        centerOfMass 0 0 0
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters { axis 0 0 1 anchor 0.2 -0.1 0.3 }
      device [
        DEF left_motor RotationalMotor {
          name \"left_motor\"
          maxTorque 10.0
        }
      ]
      endPoint Solid {
        translation 0.2 -0.1 0.3
        children [ Shape { geometry Cylinder { radius 0.1 height 0.05 } } ]
        boundingObject Cylinder { radius 0.1 height 0.05 }
        physics Physics { mass 2.0 }
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters { axis 0 0 1 anchor 0.2 -0.1 -0.3 }
      device [
        DEF right_motor RotationalMotor {
          name \"right_motor\"
          maxTorque 10.0
        }
      ]
      endPoint Solid {
        translation 0.2 -0.1 -0.3
        children [ Shape { geometry Cylinder { radius 0.1 height 0.05 } } ]
        boundingObject Cylinder { radius 0.1 height 0.05 }
        physics Physics { mass 2.0 }
      }
    }
  ]
  boundingObject Box { size 0.8 0.2 0.5 }
  physics Physics { mass 50.0 }
  controller \"<none>\"
}
'''
with open('$USER_WORLD', 'w') as f:
    f.write(wbt_content)
"

chown ga:ga "$USER_WORLD"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Clean up any previous task artifacts
rm -f /home/ga/Desktop/agv_heavy_payload.wbt 2>/dev/null || true

# Launch Webots with the scenario world
echo "Launching Webots with AGV logistics cell world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for verification evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Agent Instructions:"
echo "1. Set CUSTOM_PAYLOAD mass to 120.0"
echo "2. Set CUSTOM_PAYLOAD centerOfMass to 0.12 -0.05 0.18"
echo "3. Set left_motor and right_motor maxTorque to 80.0"
echo "4. Save to /home/ga/Desktop/agv_heavy_payload.wbt"