#!/bin/bash
echo "=== Setting up configure_smart_camera_recognition task ==="

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

USER_WORLD="/home/ga/webots_projects/agri_weeding_scenario.wbt"

# Generate the base world with the robot, camera, and weeds
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  title "Agricultural Weeding Scenario"
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.1
  position 4 4 3
}
TexturedBackground {
}
TexturedBackgroundLight {
}
Solid {
  translation 0 0 -0.1
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.4 0.3 0.1
        roughness 1
        metalness 0
      }
      geometry Plane {
        size 20 20
      }
    }
  ]
  name "ground"
  boundingObject Plane {
    size 20 20
  }
}
DEF AGRI_BOT Robot {
  translation 0 0 0.2
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.5 0.8
        roughness 0.5
      }
      geometry Box {
        size 0.6 0.4 0.2
      }
    }
    DEF CROP_CAMERA Camera {
      translation 0.3 0 0.1
      width 800
      height 600
      fieldOfView 1.0
    }
  ]
  name "agri_robot"
}
DEF WEED_1 Solid {
  translation 1.5 0.5 0.05
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0 0.8 0
        roughness 0.8
      }
      geometry Sphere {
        radius 0.1
      }
    }
  ]
  name "weed_1"
}
DEF WEED_2 Solid {
  translation 2.5 -0.4 0.05
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0 0.8 0
        roughness 0.8
      }
      geometry Sphere {
        radius 0.1
      }
    }
  ]
  name "weed_2"
}
DEF WEED_3 Solid {
  translation 3.5 0.2 0.05
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0 0.8 0
        roughness 0.8
      }
      geometry Sphere {
        radius 0.1
      }
    }
  ]
  name "weed_3"
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/agri_smart_camera.wbt

# Launch Webots with the scenario world
echo "Launching Webots with agricultural weeding scenario..."
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
echo "Waiting for agent to configure Recognition and recognitionColors..."