#!/bin/bash
# Setup script for configure_epuck_line_course task
# Generates a realistic line-following track texture and creates a baseline Webots world.

echo "=== Setting up configure_epuck_line_course task ==="

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

# Create working directories
PROJECT_DIR="/home/ga/webots_projects/line_track"
mkdir -p "$PROJECT_DIR/textures"
mkdir -p "$PROJECT_DIR/worlds"

# Generate the line-following track texture (standard robotics competition oval track)
echo "Generating track texture..."
cat > /tmp/make_track.py << 'EOF'
import math

width, height = 1024, 1024
ppm_path = '/home/ga/webots_projects/line_track/textures/track.ppm'
png_path = '/home/ga/webots_projects/line_track/textures/track.png'

with open(ppm_path, 'w') as f:
    f.write(f"P3\n{width} {height}\n255\n")
    for y in range(height):
        for x in range(width):
            # Oval track equation
            v = ((x - width/2)**2) / 160000 + ((y - height/2)**2) / 90000
            # Draw line with thickness
            if 0.85 < v < 1.15:
                f.write("0 0 0\n")  # Black line
            else:
                f.write("255 255 255\n")  # White background
EOF

python3 /tmp/make_track.py
ffmpeg -y -i "$PROJECT_DIR/textures/track.ppm" "$PROJECT_DIR/textures/track.png" 2>/dev/null
rm -f "$PROJECT_DIR/textures/track.ppm"

# Create the baseline world
echo "Creating baseline world..."
USER_WORLD="$PROJECT_DIR/worlds/line_follow_setup.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/robots/gctronic/e-puck/protos/E-puck.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/robots/gctronic/e-puck/protos/E-puckGroundSensors.proto"

WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.5773 0.5773 0.5773 2.0944
  position 0 0 2.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 1 1
}
DEF EPUCK E-puck {
  translation 0 0 0
  rotation 0 0 1 0
  controller "<none>"
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/epuck_line_follow.wbt

# Launch Webots with the baseline world
echo "Launching Webots with line follow setup world..."
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
echo "Track texture generated at: $PROJECT_DIR/textures/track.png"