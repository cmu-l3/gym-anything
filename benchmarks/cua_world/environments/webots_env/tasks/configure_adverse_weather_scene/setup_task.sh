#!/bin/bash
# Setup script for configure_adverse_weather_scene task

echo "=== Setting up adverse weather simulation task ==="

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

# Programmatically generate the starting world
USER_WORLD="/home/ga/webots_projects/outdoor_perception.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 32
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.5
  position 12 6 12
}
Background {
  skyColor [
    0.15 0.45 1
  ]
  luminosity 1.3
}
DirectionalLight {
  ambientIntensity 1
  direction 0.5 -1 -0.3
  intensity 1
  color 1 1 1
}
Solid {
  translation 0 -0.05 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.3 0.4 0.2
        roughness 0.9
      }
      geometry Box {
        size 50 0.1 50
      }
    }
  ]
  boundingObject Box {
    size 50 0.1 50
  }
}
Solid {
  translation 5 0.5 5
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.2 0.2
      }
      geometry Box {
        size 1 1 1
      }
    }
  ]
  boundingObject Box {
    size 1 1 1
  }
}
DEF FIELD_ROBOT Robot {
  translation 0 0.1 0
  children [
    Camera {
      translation 0 0.5 0
      name "perception_camera"
      width 640
      height 480
      far 20.0
    }
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
      }
      geometry Box {
        size 0.8 0.4 0.6
      }
    }
  ]
  boundingObject Box {
    size 0.8 0.4 0.6
  }
  physics Physics {
    mass 12.0
  }
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Create Desktop directory and clear previous artifacts
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/adverse_weather.wbt

# Launch Webots
echo "Launching Webots with clear weather scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Waiting for agent to apply adverse weather configuration."