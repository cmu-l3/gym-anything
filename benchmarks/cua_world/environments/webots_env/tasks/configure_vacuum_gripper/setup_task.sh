#!/bin/bash
# Setup script for configure_vacuum_gripper task

echo "=== Setting up configure_vacuum_gripper task ==="

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

# Create the task's custom world file 
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/palletizing_workcell.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.2
  position 1.5 1.5 2.0
}
Background {
  skyColor [ 0.4 0.7 1.0 ]
}
DirectionalLight {
  direction -0.5 -1 -0.5
}
Solid {
  translation 0 -0.05 0
  children [
    Shape {
      geometry Box { size 2 0.1 2 }
      appearance Appearance { material Material { diffuseColor 0.8 0.8 0.8 } }
    }
  ]
  boundingObject Box { size 2 0.1 2 }
}
DEF PALLETIZING_ROBOT Robot {
  translation 0 0 0
  children [
    DEF BASE Solid {
      children [ 
        Shape { 
          geometry Cylinder { height 0.1 radius 0.2 } 
          appearance Appearance { material Material { diffuseColor 0.2 0.2 0.2 } }
        } 
      ]
    }
    DEF WRIST_LINK Solid {
      translation 0 0.5 0
      children [
        Shape { 
          geometry Sphere { radius 0.08 } 
          appearance Appearance { material Material { diffuseColor 1 0.5 0 } } 
        }
      ]
      boundingObject Sphere { radius 0.08 }
      physics Physics { mass 2.0 }
    }
  ]
  name "PALLETIZING_ROBOT"
  boundingObject Cylinder { height 0.1 radius 0.2 }
  physics Physics { mass 15.0 }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming detection
date +%s > /tmp/task_start_timestamp

# Clean any previous outputs
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/palletizer_gripper.wbt

# Launch Webots with the scenario world
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
echo "Target output: /home/ga/Desktop/palletizer_gripper.wbt"