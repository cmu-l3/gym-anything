#!/bin/bash
# Setup script for optimize_swarm_performance task
# Generates a laggy, high-fidelity swarm world that the agent must optimize.

echo "=== Setting up optimize_swarm_performance task ==="

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

# Define working directories
PROJECT_DIR="/home/ga/webots_projects/rl_swarm"
WORLDS_DIR="$PROJECT_DIR/worlds"
mkdir -p "$WORLDS_DIR"
chown -R ga:ga "$PROJECT_DIR"

USER_WORLD="$WORLDS_DIR/training_env.wbt"

# Generate the unoptimized world file directly
echo "Generating unoptimized world file..."
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  title "Swarm RL Training"
  basicTimeStep 8
  FPS 60
  optimalThreadCount 1
  contactProperties [
    ContactProperties {
      material1 "wheel"
      material2 "floor"
      coulombFriction [ 0.8 ]
    }
  ]
}
Viewpoint {
  orientation -0.25 0.95 0.15 1.2
  position 8.0 6.0 8.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
DirectionalLight {
  ambientIntensity 1
  direction -0.5 -1 -0.5
  castShadows TRUE
}
RectangleArena {
  floorSize 10 10
}
EOF

# Add 10 dummy robots to visually simulate a small swarm and add scene weight
for i in {1..10}; do
  X=$(echo "scale=2; ($RANDOM % 800)/100 - 4.0" | bc)
  Z=$(echo "scale=2; ($RANDOM % 800)/100 - 4.0" | bc)
  cat >> "$USER_WORLD" << EOF
DEF SWARM_ROBOT_$i Robot {
  translation $X 0.1 $Z
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
        roughness 0.5
        metalness 0.5
      }
      geometry Box {
        size 0.2 0.2 0.2
      }
    }
  ]
  boundingObject Box {
    size 0.2 0.2 0.2
  }
  physics Physics {
    mass 1.0
  }
}
EOF
done

chown ga:ga "$USER_WORLD"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure Desktop directory exists and clear previous outputs
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/optimized_training_env.wbt

# Launch Webots with the training scenario world
echo "Launching Webots with RL swarm world..."
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
echo "Target optimizations:"
echo "  - WorldInfo.basicTimeStep -> 32"
echo "  - WorldInfo.optimalThreadCount -> 8 (or >= 4)"
echo "  - WorldInfo.FPS -> 20 (or <= 20)"
echo "  - DirectionalLight.castShadows -> FALSE"
echo "Save to /home/ga/Desktop/optimized_training_env.wbt"