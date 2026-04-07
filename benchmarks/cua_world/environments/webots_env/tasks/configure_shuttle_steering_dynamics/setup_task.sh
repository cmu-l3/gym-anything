#!/bin/bash
echo "=== Setting up configure_shuttle_steering_dynamics task ==="

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

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Create projects directory
mkdir -p /home/ga/webots_projects
chown ga:ga /home/ga/webots_projects

USER_WORLD="/home/ga/webots_projects/campus_shuttle_draft.wbt"

# Generate the starting world with unconstrained joints and motors
cat > "$USER_WORLD" << 'WBTEOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.2 0.9 0.2 1.3
  position 6 4 6
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 30 30
}
DEF SHUTTLE Robot {
  translation 0 0.3 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.6 0.8
        metalness 0
      }
      geometry Box {
        size 3 0.5 1.5
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
      }
      device [
        RotationalMotor {
          name "fl_steer"
          maxVelocity 100
          maxTorque 100
        }
      ]
      endPoint Solid {
        translation 1.2 0 0.8
        children [ DEF WHEEL Shape { geometry Cylinder { radius 0.3 height 0.2 } } ]
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
      }
      device [
        RotationalMotor {
          name "fr_steer"
          maxVelocity 100
          maxTorque 100
        }
      ]
      endPoint Solid {
        translation 1.2 0 -0.8
        children [ USE WHEEL ]
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 0 1
      }
      device [
        RotationalMotor {
          name "rl_drive"
          maxVelocity 100
          maxTorque 10
        }
      ]
      endPoint Solid {
        translation -1.2 0 0.8
        children [ USE WHEEL ]
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 0 1
      }
      device [
        RotationalMotor {
          name "rr_drive"
          maxVelocity 100
          maxTorque 10
        }
      ]
      endPoint Solid {
        translation -1.2 0 -0.8
        children [ USE WHEEL ]
      }
    }
  ]
  name "SHUTTLE"
  boundingObject Box {
    size 3 0.5 1.5
  }
  physics Physics {
    density -1
    mass 2000
  }
}
WBTEOF

chown ga:ga "$USER_WORLD"

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/shuttle_dynamics.wbt

# Launch Webots
echo "Launching Webots with campus shuttle scenario..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize Webots
focus_webots

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: Configure physical limits and motor specs for all 4 wheels."
echo "Save output to: /home/ga/Desktop/shuttle_dynamics.wbt"