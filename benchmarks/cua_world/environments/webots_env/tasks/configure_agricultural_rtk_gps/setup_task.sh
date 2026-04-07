#!/bin/bash
echo "=== Setting up configure_agricultural_rtk_gps task ==="

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

# Generate the baseline world file
USER_WORLD="/home/ga/webots_projects/vineyard_scenario.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  gpsCoordinateSystem "local"
  gpsReference 0 0 0
  northDirection 1 0 0
}
Viewpoint {
  orientation -0.5773 0.5773 0.5773 2.0944
  position 0 0 15
}
TexturedBackground {
}
TexturedBackgroundLight {
}
Floor {
  size 100 100
  appearance PBRAppearance {
    baseColor 0.4 0.3 0.2
    roughness 1
    metalness 0
  }
}
DEF AG_TRACTOR Robot {
  translation 0 0 0.5
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.1 0.1
        roughness 0.5
        metalness 0.2
      }
      geometry Box {
        size 2 4 1
      }
    }
    DEF rtk_gps GPS {
      name "rtk_gps"
      accuracy 0
    }
  ]
  name "AG_TRACTOR"
  boundingObject Box {
    size 2 4 1
  }
  physics Physics {
    mass 2500
  }
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/vineyard_georeferenced.wbt

# Launch Webots with the generated world
echo "Launching Webots with vineyard scenario world..."
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
echo "  1. Set WorldInfo gpsCoordinateSystem to 'WGS84'"
echo "  2. Set WorldInfo gpsReference to 38.281 -122.278 25.5"
echo "  3. Set WorldInfo northDirection to 0 1 0"
echo "  4. Set AG_TRACTOR's rtk_gps accuracy to 0.02"
echo "  5. Save world to /home/ga/Desktop/vineyard_georeferenced.wbt"