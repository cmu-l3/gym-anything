#!/bin/bash
echo "=== Setting up configure_orbital_docking_connectors task ==="

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

# Create the task's custom world file programmatically
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/satellite_rendezvous.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  gravity 0
}
Viewpoint {
  orientation -0.15 0.9 0.4 1.7
  position 1.5 1.5 1.5
}
Background {
  skyColor [ 0.1 0.1 0.1 ]
}
DEF CHASER_SATELLITE Robot {
  translation 0 0 0
  children [
    Connector {
      name "docking_port"
      type "symmetric"
      distanceTolerance 0.005
      tensileStrength 50.0
    }
  ]
}
DEF TARGET_SATELLITE Robot {
  translation 0.5 0 0
  children [
    Connector {
      name "docking_port"
      type "passive"
      distanceTolerance 0.005
    }
  ]
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/orbital_docking.wbt

# Launch Webots with the scenario world
echo "Launching Webots with satellite scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot showing starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="