#!/bin/bash
# Setup script for configure_tugger_solidreference task
# Generates the starting .wbt file with disconnected robot and cart, then launches Webots.

echo "=== Setting up configure_tugger_solidreference task ==="

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

# Create workspace and write the starting world file
USER_WORLD="/home/ga/webots_projects/tugger_train.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.9 0.3 1.1
  position 4 3 3
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 10 10
}
DEF TUGGER_ROBOT Robot {
  translation 0 0 0.1
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.5 0.8
      }
      geometry Box {
        size 0.6 0.4 0.2
      }
    }
    HingeJoint {
      jointParameters HingeJointParameters {
        anchor 0 0 0
        axis 1 0 0
      }
      device [
        RotationalMotor {
          name "hitch_motor"
        }
      ]
      endPoint NULL
    }
  ]
  name "tugger"
  boundingObject Box {
    size 0.6 0.4 0.2
  }
  physics Physics {
    mass 50.0
  }
}
DEF MATERIAL_CART Solid {
  translation -1.5 0 0.1
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
      }
      geometry Box {
        size 0.8 0.5 0.2
      }
    }
  ]
  name "MATERIAL_CART"
  boundingObject Box {
    size 0.8 0.5 0.2
  }
  physics Physics {
    mass 100.0
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
rm -f /home/ga/Desktop/tugger_linked.wbt

# Launch Webots with the tugger scenario world
echo "Launching Webots with tugger train world..."
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
echo "  1. Find TUGGER_ROBOT -> HingeJoint -> change endPoint to SolidReference"
echo "  2. Set solidName to 'MATERIAL_CART'"
echo "  3. Configure jointParameters: axis 0 0 1, anchor -1.2 0 0.15, dampingConstant 2.5"
echo "  4. Save to /home/ga/Desktop/tugger_linked.wbt"