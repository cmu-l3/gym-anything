#!/bin/bash
# Setup script for configure_gripper_contact_physics task
# Generates a fresh grasp scenario world with default materials and loads it in Webots.

echo "=== Setting up configure_gripper_contact_physics task ==="

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

# Define paths
USER_PROJECT_DIR="/home/ga/webots_projects"
USER_WORLD="$USER_PROJECT_DIR/grasp_scenario.wbt"
mkdir -p "$USER_PROJECT_DIR"

# Generate the base world with default physics
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.2
  position 1.2 0.8 1.2
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 2 2
}
DEF TARGET_OBJECT Solid {
  translation 0 0.05 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.8 1
        roughness 0.1
      }
      geometry Cylinder {
        height 0.1
        radius 0.03
      }
    }
  ]
  boundingObject Cylinder {
    height 0.1
    radius 0.03
  }
  physics Physics {
    mass 0.5
  }
  contactMaterial "default"
}
DEF ROBOT_ARM Robot {
  translation 0 0.1 0
  children [
    DEF LEFT_PAD Solid {
      translation -0.06 0 0
      children [
        Shape {
          appearance PBRAppearance {
            baseColor 0.8 0.2 0.2
          }
          geometry Box {
            size 0.02 0.05 0.05
          }
        }
      ]
      boundingObject Box {
        size 0.02 0.05 0.05
      }
      physics Physics {
        mass 0.1
      }
      contactMaterial "default"
    }
    DEF RIGHT_PAD Solid {
      translation 0.06 0 0
      children [
        Shape {
          appearance PBRAppearance {
            baseColor 0.8 0.2 0.2
          }
          geometry Box {
            size 0.02 0.05 0.05
          }
        }
      ]
      boundingObject Box {
        size 0.02 0.05 0.05
      }
      physics Physics {
        mass 0.1
      }
      contactMaterial "default"
    }
  ]
}
EOF

chown -R ga:ga "$USER_PROJECT_DIR"

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Clean up any potential previous output file
mkdir -p /home/ga/Desktop
rm -f /home/ga/Desktop/slippery_grasp.wbt

# Launch Webots
echo "Launching Webots with grasp scenario..."
launch_webots_with_world "$USER_WORLD"
sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent must assign materials 'silicone' and 'glass' and create a ContactProperties node."