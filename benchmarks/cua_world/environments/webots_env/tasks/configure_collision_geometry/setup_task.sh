#!/bin/bash
echo "=== Setting up configure_collision_geometry task ==="

source /workspace/scripts/task_utils.sh

export LIBGL_ALWAYS_SOFTWARE=1
WEBOTS_HOME=$(detect_webots_home)

if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

mkdir -p /home/ga/webots_projects/collision_debug/worlds
USER_WORLD="/home/ga/webots_projects/collision_debug/worlds/collision_debug.wbt"

# Dynamically generate the baseline world with NULL boundingObjects
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 32
  contactProperties [
    ContactProperties {
      material1 "default"
      material2 "default"
    }
  ]
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.2
  position 3.5 2.5 3.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 4 4
}
DEF MOBILE_ROBOT Robot {
  translation 0 0.15 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
        roughness 0.5
      }
      geometry Box {
        size 0.4 0.2 0.3
      }
    }
  ]
  boundingObject NULL
  physics Physics {
    mass 2.5
  }
}
DEF OBSTACLE_BOX Solid {
  translation 1.2 0.2 0.8
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.1 0.1
        roughness 0.5
      }
      geometry Box {
        size 0.6 0.6 0.4
      }
    }
  ]
  boundingObject NULL
  physics Physics {
    mass 5.0
  }
}
DEF OBSTACLE_CYLINDER Solid {
  translation -0.8 0.25 -0.6
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.1 0.1 0.8
        roughness 0.5
      }
      geometry Cylinder {
        height 0.5
        radius 0.2
      }
    }
  ]
  boundingObject NULL
  physics Physics {
    mass 3.0
  }
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/collision_fixed.wbt

# Launch Webots with the debug scenario world
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
echo "Target output: /home/ga/Desktop/collision_fixed.wbt"