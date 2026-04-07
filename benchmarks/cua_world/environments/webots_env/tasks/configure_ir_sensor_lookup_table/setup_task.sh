#!/bin/bash
echo "=== Setting up configure_ir_sensor_lookup_table task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Record timestamp for anti-gaming (detect if agent actually created the file)
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/webots_projects"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# Generate the initial world file with the generic sensor
USER_WORLD="$PROJECT_DIR/micromouse_maze.wbt"
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.5773 0.5773 0.5773 2.0944
  position 0 0 1.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 1 1
}
Robot {
  translation 0 0 0.05
  name "MICROMOUSE"
  children [
    DistanceSensor {
      translation 0.05 0 0
      name "front_ir"
      type "generic"
      lookupTable [
        0 1000 0
        1 0 0
      ]
    }
  ]
}
EOF

chown ga:ga "$USER_WORLD"
chmod 644 "$USER_WORLD"

# Create Desktop directory for the output file
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/micromouse_calibrated.wbt

# Launch Webots with the scenario
echo "Launching Webots..."
launch_webots_with_world "$USER_WORLD"
sleep 6

# Maximize and focus Webots window
focus_webots

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot to document start state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent must edit the 'front_ir' DistanceSensor type and lookupTable, then save to Desktop."