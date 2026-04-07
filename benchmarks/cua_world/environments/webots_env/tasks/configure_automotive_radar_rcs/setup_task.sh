#!/bin/bash
# Setup script for configure_automotive_radar_rcs task
# Generates a synthetic ADAS scenario world with misconfigured radar and missing RCS,
# then launches it in Webots.

echo "=== Setting up configure_automotive_radar_rcs task ==="

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

USER_WORLD="/home/ga/webots_projects/acc_highway_test.wbt"

# Generate the starting world file
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.05 0.95 0.3 1.57
  position -15 2 1
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 200 10
}
DEF EGO_VEHICLE Robot {
  translation 0 0.25 0
  name "ego_vehicle"
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.1 0.2 0.8
        roughness 0.5
      }
      geometry Box {
        size 4 1 2
      }
    }
    DEF front_radar Radar {
      translation 2 0 0
      name "front_radar"
      maxRange 50.0
      horizontalFieldOfView 1.57
      rangeNoise 0.0
    }
  ]
  boundingObject Box {
    size 4 1 2
  }
  physics Physics {
    mass 1500
  }
}
DEF LEAD_VEHICLE Robot {
  translation 80 0.25 0
  name "lead_vehicle"
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.1 0.1
        roughness 0.5
      }
      geometry Box {
        size 4 1 2
      }
    }
  ]
  boundingObject Box {
    size 4 1 2
  }
  physics Physics {
    mass 1500
  }
  radarCrossSection 0.0
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/acc_highway_configured.wbt

# Launch Webots with the scenario world
echo "Launching Webots with ACC highway scenario world..."
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
echo "Agent should find nodes in the scene tree and reconfigure:"
echo "  - front_radar: maxRange 50.0->250.0, horizontalFieldOfView 1.57->0.314, rangeNoise 0.0->0.1"
echo "  - LEAD_VEHICLE: radarCrossSection 0.0->100.0"
echo "  - Save to: /home/ga/Desktop/acc_highway_configured.wbt"