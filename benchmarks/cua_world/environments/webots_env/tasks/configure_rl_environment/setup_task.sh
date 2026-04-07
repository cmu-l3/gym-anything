#!/bin/bash
echo "=== Setting up configure_rl_environment task ==="

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
chown ga:ga /home/ga/Desktop

# Dynamically generate the starting world file to ensure self-containment
USER_WORLD="/home/ga/webots_projects/rl_env.wbt"
cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/robots/gctronic/e-puck/protos/E-puck.proto"

WorldInfo {
  basicTimeStep 32
  randomSeed 0
}
Viewpoint {
  orientation -0.5773 0.5773 0.5773 2.0944
  position 0 0 2
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 1 1
}
Solid {
  translation 0.2 0.2 0.05
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 1 0 0
        roughness 1
        metalness 0
      }
      geometry Sphere {
        radius 0.05
      }
    }
  ]
  boundingObject Sphere {
    radius 0.05
  }
  physics Physics {
  }
}
DEF AGENT E-puck {
  translation -0.2 -0.2 0
  controller "heuristic_nav"
  supervisor FALSE
}
EOF

chown ga:ga "$USER_WORLD"

# Remove any previous output file
rm -f /home/ga/Desktop/rl_env_ready.wbt

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp.txt

# Launch Webots with the starting world
echo "Launching Webots with RL baseline world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the Webots window
focus_webots

# Dismiss any popup dialogs that might appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take an initial screenshot to record the starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent instructions:"
echo "  1. WorldInfo: basicTimeStep -> 16, randomSeed -> 42"
echo "  2. DEF AGENT: controller -> \"<extern>\", supervisor -> TRUE"
echo "  3. Solid (with red Sphere): assign DEF name RL_TARGET"
echo "  4. Save as: /home/ga/Desktop/rl_env_ready.wbt"