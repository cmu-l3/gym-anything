#!/bin/bash
echo "=== Setting up configure_camera_sim_to_real task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any existing output to ensure a clean slate
rm -f /home/ga/Desktop/sim_to_real_camera.wbt

# Create the starting scenario world programmatically to ensure perfect initial state
mkdir -p /home/ga/webots_projects
WORLD_FILE="/home/ga/webots_projects/sim_to_real_scenario.wbt"

cat > "$WORLD_FILE" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.1 0.9 0.4 1.7
  position 3.0 2.5 3.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
Floor {
  size 10 10
}
DEF DELIVERY_BOT Robot {
  translation 0 0.1 0
  children [
    Shape {
      geometry Box { size 0.4 0.2 0.6 }
      appearance PBRAppearance { baseColor 0.8 0.2 0.2 }
    }
    Camera {
      translation 0 0.2 -0.3
      name "front_camera"
      width 640
      height 480
      noise 0.0
      motionBlur 0.0
    }
  ]
  name "delivery_bot"
  boundingObject Box { size 0.4 0.2 0.6 }
  physics Physics { mass 20.0 }
}
EOF
chown -R ga:ga /home/ga/webots_projects

# Ensure Webots environment variables are correctly loaded
export LIBGL_ALWAYS_SOFTWARE=1
WEBOTS_HOME=$(detect_webots_home)

# Launch Webots with our custom scenario
echo "Launching Webots..."
launch_webots_with_world "$WORLD_FILE"
sleep 5

# Ensure the window is focused and maximized for the agent
focus_webots

# Dismiss any stray dialogs like guided tours
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Capture evidence of the starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="