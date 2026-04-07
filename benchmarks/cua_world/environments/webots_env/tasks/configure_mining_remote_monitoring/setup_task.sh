#!/bin/bash
# Setup script for configure_mining_remote_monitoring task
# Generates the base scenario with placeholder values.

echo "=== Setting up configure_mining_remote_monitoring task ==="

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

# Create the project directory and the starting world file
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/mining_scenario.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "https://raw.githubusercontent.com/cyberbotics/webots/R2023b/projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
}
Viewpoint {
  orientation -0.25 0.94 0.22 1.54
  position 2.0 1.5 -2.0
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
}
DEF MINING_ROBOT Robot {
  translation 0 0.05 0
  children [
    Shape {
      geometry Box {
        size 0.2 0.1 0.3
      }
    }
    DEF radio_emitter Emitter {
      channel 0
      range 10
    }
    DEF status_display Display {
      width 64
      height 32
    }
  ]
  name "mining_robot"
  boundingObject Box {
    size 0.2 0.1 0.3
  }
  physics Physics {
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/mining_robot_configured.wbt

# Launch Webots with the scenario world
echo "Launching Webots with mining scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent should:"
echo "  1. Emitter 'radio_emitter': change range to 500, channel to 7"
echo "  2. Display 'status_display': change width to 320, height to 240"
echo "  3. Add Fog node at world level: visibilityRange=50.0, fogType=\"EXPONENTIAL\""
echo "  4. Save to /home/ga/Desktop/mining_robot_configured.wbt"