#!/bin/bash
# Setup script for configure_scrubber_coverage_battery task
# Generates a basic factory scenario with a scrubber robot missing its Pen and battery config.

echo "=== Setting up configure_scrubber_coverage_battery task ==="

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

# Generate the starting world file
USER_WORLD="/home/ga/webots_projects/factory_scrubber.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.2
  position 4.0 3.0 4.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 20 20
  floorAppearance PBRAppearance {
    baseColor 0.8 0.8 0.8
    roughness 0.5
    metalness 0
  }
}
DEF SCRUBBER_ROBOT Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
        metalness 0
      }
      geometry Box {
        size 0.65 0.2 0.8
      }
    }
  ]
  name "scrubber"
  boundingObject Box {
    size 0.65 0.2 0.8
  }
  physics Physics {
    mass 150.0
  }
  controller "<generic>"
  battery []
}
EOF

chown ga:ga "$USER_WORLD"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/factory_scrubber_configured.wbt

# Launch Webots with the scrubber scenario world
echo "Launching Webots with scrubber scenario world..."
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
echo "  1. Find SCRUBBER_ROBOT and add Pen to children (name: 'cleaning_trace', inkColor: 0 0 1, leadSize: 0.65, maxDistance: 0.5, write: TRUE)"
echo "  2. Configure battery field to [8640000, 8640000, 2000]"
echo "  3. Save to /home/ga/Desktop/factory_scrubber_configured.wbt"