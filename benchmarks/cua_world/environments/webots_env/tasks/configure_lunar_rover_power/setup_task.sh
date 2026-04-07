#!/bin/bash
echo "=== Setting up configure_lunar_rover_power task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 2

# Create the lunar mission starting world
mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/lunar_mission.wbt"

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 32
  gravity 1.62
}
Viewpoint {
  orientation -0.25 0.9 0.35 1.1
  position 3.0 2.0 4.0
}
TexturedBackground {
  texture "mars"
}
TexturedBackgroundLight {
  luminosity 1.5
}
Floor {
  size 20 20
  appearance PBRAppearance {
    baseColor 0.6 0.6 0.6
    roughness 1
    metalness 0
  }
}
DEF LUNAR_ROVER Robot {
  translation 0 0.1 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
        roughness 0.5
        metalness 0.5
      }
      geometry Box {
        size 0.8 0.3 1.2
      }
    }
    DEF SOLAR_PANEL LightSensor {
      translation 0 0.16 0
      rotation 0 0 1 0
      name "solar_panel"
      lookupTable [
        0 0 0
        1000 1000 0
      ]
    }
  ]
  name "lunar_rover"
  battery []
  cpuConsumption 10
}
EOF

chown ga:ga "$USER_WORLD"

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/lunar_power_sim.wbt

# Launch Webots with the lunar scenario world
echo "Launching Webots with lunar mission world..."
launch_webots_with_world "$USER_WORLD"

sleep 6

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
echo "  1. Configure battery to [10000, 36000, 50]"
echo "  2. Configure solar_panel LightSensor: rotation to '0 1 0 -1.5708'"
echo "  3. Configure solar_panel fieldOfView to 3.1415"
echo "  4. Configure solar_panel lookupTable to [0 0 0, 1361 50 0]"
echo "  5. Save to /home/ga/Desktop/lunar_power_sim.wbt"