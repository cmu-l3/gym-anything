#!/bin/bash
echo "=== Setting up configure_ptz_camera_optics task ==="

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
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/webots_projects
chown ga:ga /home/ga/Desktop

USER_WORLD="/home/ga/webots_projects/pipeline_crawler.wbt"

# Generate the starting world with a basic, unconfigured camera
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.1
  position 1.5 1.5 3.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
DEF CRAWLER_ROBOT Robot {
  name "pipeline_crawler"
  children [
    DEF INSPECTION_CAMERA Camera {
      name "inspection_camera"
      width 64
      height 64
      fieldOfView 1.047
    }
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
        metalness 0.5
      }
      geometry Box {
        size 0.4 0.2 0.6
      }
    }
  ]
  boundingObject Box {
    size 0.4 0.2 0.6
  }
  physics Physics {
    mass 10
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Remove any previous output file
rm -f /home/ga/Desktop/ptz_inspection_camera.wbt

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch Webots with the pipeline crawler world
echo "Launching Webots with pipeline crawler world..."
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
echo "  1. Find CRAWLER_ROBOT -> inspection_camera"
echo "  2. Update resolution to 1920x1080 and FOV to 1.57"
echo "  3. Add a Focus node and configure focalLength(0.05), minFocalDistance(0.1), maxFocalDistance(10.0)"
echo "  4. Add a Zoom node and configure maxFieldOfView(1.57), minFieldOfView(0.157)"
echo "  5. Save world to /home/ga/Desktop/ptz_inspection_camera.wbt"