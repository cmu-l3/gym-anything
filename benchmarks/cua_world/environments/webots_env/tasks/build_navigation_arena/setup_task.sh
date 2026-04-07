#!/bin/bash
echo "=== Setting up build_navigation_arena task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create base world dynamically
mkdir -p /home/ga/webots_projects/navigation_arena/worlds
cat > /home/ga/webots_projects/navigation_arena/worlds/benchmark_base.wbt << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectArena.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/robots/adept/pioneer3/protos/Pioneer3dx.proto"

WorldInfo {
  title "Untitled"
  basicTimeStep 64
}
Viewpoint {
  orientation -0.25 0.9 0.3 1.2
  position 5.5 4.5 5.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectArena {
  floorSize 4 4
}
DEF BENCHMARK_ROBOT Pioneer3dx {
  translation 0 0.1 0
  controller "random_wander"
  extensionSlot [
    DEF lidar Lidar {
      translation 0 0.3 0
      numberOfLayers 2
      maxRange 10
      fieldOfView 1.5708
      horizontalResolution 128
    }
  ]
}
EOF

# Set permissions
chown -R ga:ga /home/ga/webots_projects

# Make sure desktop directory exists and clear any previous outputs
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/navigation_benchmark.wbt

# Launch Webots with the base world
export LIBGL_ALWAYS_SOFTWARE=1
launch_webots_with_world "/home/ga/webots_projects/navigation_arena/worlds/benchmark_base.wbt"
sleep 5

# Focus window and clear dialogs
focus_webots
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="