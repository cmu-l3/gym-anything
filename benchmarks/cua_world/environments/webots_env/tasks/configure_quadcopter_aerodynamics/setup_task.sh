#!/bin/bash
echo "=== Setting up configure_quadcopter_aerodynamics task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

# Create the drone testing world inline to guarantee exact node structures
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/drone_testing.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 8
  title "Quadcopter Test Stand"
}
Viewpoint {
  orientation -0.24 0.94 0.23 1.2
  position 1.8 1.5 1.8
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 10 10
}
DEF DELIVERY_DRONE Robot {
  translation 0 0 0.2
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
        metalness 0.5
      }
      geometry Box {
        size 0.2 0.05 0.2
      }
    }
    DEF FRONT_RIGHT_PROPELLER Propeller {
      thrustConstants 0.1 0
      torqueConstants 0.1 0
      fastHelixThreshold 24.0
      device RotationalMotor {
        name "fr_motor"
      }
    }
    DEF FRONT_LEFT_PROPELLER Propeller {
      thrustConstants 0.1 0
      torqueConstants 0.1 0
      fastHelixThreshold 24.0
      device RotationalMotor {
        name "fl_motor"
      }
    }
    DEF REAR_RIGHT_PROPELLER Propeller {
      thrustConstants 0.1 0
      torqueConstants 0.1 0
      fastHelixThreshold 24.0
      device RotationalMotor {
        name "rr_motor"
      }
    }
    DEF REAR_LEFT_PROPELLER Propeller {
      thrustConstants 0.1 0
      torqueConstants 0.1 0
      fastHelixThreshold 24.0
      device RotationalMotor {
        name "rl_motor"
      }
    }
  ]
  name "drone"
  boundingObject Box {
    size 0.2 0.05 0.2
  }
  physics Physics {
    mass 1.5
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/tuned_quadcopter.wbt

# Launch Webots with the drone scenario world
echo "Launching Webots with drone testing world..."
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
echo "Agent should navigate the scene tree, find the 4 Propeller nodes under DELIVERY_DRONE, and edit:"
echo "  - thrustConstants -> 0.00015 0"
echo "  - torqueConstants -> 0.000006 0"
echo "  - fastHelixThreshold -> 75.0"
echo "And save to /home/ga/Desktop/tuned_quadcopter.wbt"