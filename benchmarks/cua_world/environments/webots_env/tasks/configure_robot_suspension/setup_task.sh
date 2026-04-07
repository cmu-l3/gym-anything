#!/bin/bash
# Setup script for configure_robot_suspension task

echo "=== Setting up configure_robot_suspension task ==="

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

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create working directory
mkdir -p /home/ga/webots_projects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/webots_projects /home/ga/Desktop

USER_WORLD="/home/ga/webots_projects/rover_suspension.wbt"
rm -f /home/ga/Desktop/rover_fixed.wbt 2>/dev/null || true

# Generate the initial buggy world dynamically
echo "Generating initial buggy world file..."
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.1
  position 4.0 3.0 4.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 10 10
}
DEF DELIVERY_ROVER Robot {
  translation 0 0.2 0
  children [
    DEF CHASSIS_SHAPE Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
        metalness 0.2
      }
      geometry Box {
        size 0.6 0.2 0.8
      }
    }
    DEF FL_WHEEL_JOINT HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        suspensionSpringConstant 0
        suspensionDampingConstant 0
        suspensionAxis 1 0 0
      }
      device [ RotationalMotor { name "fl_motor" } ]
      endPoint Solid {
        translation -0.35 0 0.3
        children [ DEF WHEEL_SHAPE Shape { appearance PBRAppearance { baseColor 0.2 0.2 0.2 } geometry Cylinder { radius 0.15 height 0.1 } } ]
        physics Physics { mass 5 }
      }
    }
    DEF FR_WHEEL_JOINT HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        suspensionSpringConstant 0
        suspensionDampingConstant 0
        suspensionAxis 1 0 0
      }
      device [ RotationalMotor { name "fr_motor" } ]
      endPoint Solid {
        translation 0.35 0 0.3
        children [ USE WHEEL_SHAPE ]
        physics Physics { mass 5 }
      }
    }
    DEF RL_WHEEL_JOINT HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        suspensionSpringConstant 0
        suspensionDampingConstant 0
        suspensionAxis 1 0 0
      }
      device [ RotationalMotor { name "rl_motor" } ]
      endPoint Solid {
        translation -0.35 0 -0.3
        children [ USE WHEEL_SHAPE ]
        physics Physics { mass 5 }
      }
    }
    DEF RR_WHEEL_JOINT HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
        suspensionSpringConstant 0
        suspensionDampingConstant 0
        suspensionAxis 1 0 0
      }
      device [ RotationalMotor { name "rr_motor" } ]
      endPoint Solid {
        translation 0.35 0 -0.3
        children [ USE WHEEL_SHAPE ]
        physics Physics { mass 5 }
      }
    }
  ]
  name "delivery_rover"
  boundingObject USE CHASSIS_SHAPE
  physics Physics {
    density -1
    mass 150
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Launch Webots with the scenario
echo "Launching Webots..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any UI dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing the initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="