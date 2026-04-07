#!/bin/bash
# Setup script for configure_asv_hydrodynamics task

echo "=== Setting up configure_asv_hydrodynamics task ==="

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

# Create a valid starting world programmatically 
USER_WORLD="/home/ga/webots_projects/asv_ocean_scenario.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.1
  position 4 3 4
}
TexturedBackground {
}
TexturedBackgroundLight {
}
Fluid {
  translation 0 0 0
  name "water"
  density 1.2
  boundingObject Plane {
    size 20 20
  }
}
DEF ASV_BATHYMETRY Robot {
  translation 0 0.5 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.3 0.1
        roughness 0.5
        metalness 0.5
      }
      geometry Box {
        size 1 0.2 0.5
      }
    }
  ]
  boundingObject Box {
    size 1 0.2 0.5
  }
  physics Physics {
    density -1
    mass 15
    centerOfMass [ ]
  }
}
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/asv_configured.wbt

# Launch Webots with the programmatic scenario world
echo "Launching Webots with ASV scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 6

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Waiting for agent to apply hydrodynamics properties and save."