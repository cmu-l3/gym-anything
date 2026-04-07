#!/bin/bash
# Setup script for configure_sar_tracked_vehicle task
# Programmatically generates a starting Webots world with Track nodes
# that have incorrect placeholder values, then launches Webots.

echo "=== Setting up configure_sar_tracked_vehicle task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 2

# Create the working directory
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/sar_rubble.wbt"

# Generate the starting world file with incorrect placeholder values
python3 -c "
world_content = '''#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.95 0.15 1.5
  position 1.5 1.0 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 5 5
}
DEF SAR_ROBOT Robot {
  translation 0 0.1 0
  children [
    DEF LEFT_TRACK Track {
      translation 0 0.2 0
      device [
        LinearMotor {
          name \"left_motor\"
          maxVelocity 10.0
          maxForce 10.0
        }
      ]
      geometries [
        TrackWheel {
          position 0.2 0
          radius 0.01
        }
        TrackWheel {
          position -0.2 0
          radius 0.01
        }
      ]
    }
    DEF RIGHT_TRACK Track {
      translation 0 -0.2 0
      device [
        LinearMotor {
          name \"right_motor\"
          maxVelocity 10.0
          maxForce 10.0
        }
      ]
      geometries [
        TrackWheel {
          position 0.2 0
          radius 0.01
        }
        TrackWheel {
          position -0.2 0
          radius 0.01
        }
      ]
    }
  ]
  name \"sar_robot\"
  boundingObject Box {
    size 0.5 0.3 0.1
  }
  physics Physics {
    mass 50.0
  }
}
'''
with open('$USER_WORLD', 'w') as f:
    f.write(world_content)
"
chown ga:ga "$USER_WORLD"

# Record timestamps for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory and clear previous output
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/sar_robot_configured.wbt

# Launch Webots with the starting world
echo "Launching Webots..."
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
echo "  1. Modify LEFT_TRACK -> left_motor: maxVelocity=1.2, maxForce=800.0"
echo "  2. Modify LEFT_TRACK -> TrackWheels (x2): radius=0.08"
echo "  3. Modify RIGHT_TRACK -> right_motor: maxVelocity=1.2, maxForce=800.0"
echo "  4. Modify RIGHT_TRACK -> TrackWheels (x2): radius=0.08"
echo "  5. Save world to /home/ga/Desktop/sar_robot_configured.wbt"