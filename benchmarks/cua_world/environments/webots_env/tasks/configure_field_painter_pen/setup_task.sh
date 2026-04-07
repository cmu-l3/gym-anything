#!/bin/bash
# Setup script for configure_field_painter_pen task
# Generates a Webots world with a PAINTER_ROBOT and a misconfigured Pen device.

echo "=== Setting up configure_field_painter_pen task ==="

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
USER_WORLD="/home/ga/webots_projects/painter_robot.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  title "Autonomous Field Painter Configuration"
}
Viewpoint {
  orientation -0.27 0.65 0.70 2.26
  position 1.5 2.5 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 10 10
  floorTileSize 1 1
}
DEF PAINTER_ROBOT Robot {
  translation 0 0.045 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.5 0.8
        roughness 1
        metalness 0
      }
      geometry Box {
        size 0.4 0.1 0.6
      }
    }
    Pen {
      translation 0 -0.045 0
      rotation 1 0 0 -1.5708
      name "paint_sprayer"
      inkColor 1 0 0
      inkDensity 0.3
      leadSize 0.02
      maxDistance 0.01
    }
  ]
  name "PAINTER_ROBOT"
  boundingObject Box {
    size 0.4 0.1 0.6
  }
  physics Physics {
    density -1
    mass 15
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
rm -f /home/ga/Desktop/field_painter_configured.wbt

# Launch Webots with the painter scenario world
echo "Launching Webots with painter robot scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing the initial state
take_screenshot /tmp/task_initial.png

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent should navigate to PAINTER_ROBOT > children > paint_sprayer (Pen)"
echo "And configure the following:"
echo "  - inkColor: 1 0 0 -> 1 1 1"
echo "  - inkDensity: 0.3 -> 1.0"
echo "  - leadSize: 0.02 -> 0.12"
echo "  - maxDistance: 0.01 -> 0.06"
echo "Finally save to: /home/ga/Desktop/field_painter_configured.wbt"