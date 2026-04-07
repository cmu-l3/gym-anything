#!/bin/bash
# Setup script for configure_air_hockey_dynamics task
# Generates a minimal air hockey world and launches Webots.

echo "=== Setting up configure_air_hockey_dynamics task ==="

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

# Generate the minimal air hockey world file
USER_WORLD="/home/ga/webots_projects/air_hockey_training.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  position 0 2 1.5
  orientation -1 0 0 0.9
}
TexturedBackground {}
TexturedBackgroundLight {}
DEF TABLE Solid {
  translation 0 0 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
        roughness 0.2
        metalness 0
      }
      geometry Plane {
        size 2 1
      }
    }
  ]
  contactMaterial "table"
  boundingObject Plane {
    size 2 1
  }
}
DEF WALL Solid {
  translation 0 0 -0.5
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.2 0.2 0.8
      }
      geometry Box {
        size 2 0.1 0.1
      }
    }
  ]
  contactMaterial "wall"
  boundingObject Box {
    size 2 0.1 0.1
  }
}
DEF PUCK Solid {
  translation 0 0.05 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.9 0.1 0.1
      }
      geometry Cylinder {
        radius 0.05
        height 0.02
      }
    }
  ]
  contactMaterial "puck"
  boundingObject Cylinder {
    radius 0.05
    height 0.02
  }
  physics Physics {
    mass 0.05
  }
}
DEF STRIKER Solid {
  translation 0.5 0.05 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.1 0.9 0.1
      }
      geometry Cylinder {
        radius 0.08
        height 0.05
      }
    }
  ]
  contactMaterial "striker"
  boundingObject Cylinder {
    radius 0.08
    height 0.05
  }
  physics Physics {
    mass 0.2
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
rm -f /home/ga/Desktop/air_hockey_ready.wbt

# Launch Webots with the scenario world
echo "Launching Webots with air hockey world..."
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
echo "Agent should define ContactProperties in WorldInfo for:"
echo "  - puck & table: friction=0.002"
echo "  - puck & wall: bounce=0.95, bounceVelocity=0.05"
echo "  - puck & striker: bounce=0.85"