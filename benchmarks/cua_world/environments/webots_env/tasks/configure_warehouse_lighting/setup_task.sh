#!/bin/bash
echo "=== Setting up configure_warehouse_lighting task ==="

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

# Create the starting world file with default/incorrect lighting
USER_WORLD="/home/ga/webots_projects/warehouse_lighting_start.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  info [ "Warehouse lighting configuration task" ]
  basicTimeStep 16
}
Viewpoint {
  orientation -0.2 0.9 0.3 1.2
  position 8 5 8
}
Background {
  skyColor [ 0.4 0.7 1.0 ]
  luminosity 1.0
}
DirectionalLight {
  direction 0 -1 0
  intensity 1.0
  color 1 1 1
  castShadows FALSE
}
Solid {
  translation 0 -0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
        roughness 1
      }
      geometry Box {
        size 20 0.2 20
      }
    }
  ]
  boundingObject Box {
    size 20 0.2 20
  }
}
Solid {
  translation 0 0.5 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.4 0.8
        roughness 0.5
      }
      geometry Box {
        size 1 1 1
      }
    }
  ]
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Clean up any previous attempts
rm -f /home/ga/Desktop/warehouse_lighting.wbt

# Launch Webots
echo "Launching Webots with warehouse world..."
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