#!/bin/bash
set -e
echo "=== Setting up Configure Fleet Communication task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source utilities
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
USER_PROJECTS="/home/ga/webots_projects"
mkdir -p "$USER_PROJECTS"
chown ga:ga "$USER_PROJECTS"

WORLD_FILE="$USER_PROJECTS/warehouse_comms_broken.wbt"

# Create the broken world file directly
cat > "$WORLD_FILE" << 'WORLDEOF'
#VRML_SIM R2023b utf8

EXTERNPROTO "webots://projects/objects/backgrounds/protos/TexturedBackground.proto"
EXTERNPROTO "webots://projects/objects/backgrounds/protos/TexturedBackgroundLight.proto"
EXTERNPROTO "webots://projects/objects/floors/protos/RectangleArena.proto"

WorldInfo {
  info [
    "Warehouse fleet communication test"
  ]
  title "Warehouse Robot Fleet"
  basicTimeStep 32
}
Viewpoint {
  orientation -0.577 0.577 0.577 2.094
  position 0 0 14
}
TexturedBackground {
}
TexturedBackgroundLight {
}
RectangleArena {
  floorSize 10 10
  wallHeight 0.3
}
DEF ROBOT_A Robot {
  translation -3 2 0.06
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.9 0.1 0.1
        roughness 0.5
        metalness 0
      }
      geometry Cylinder {
        height 0.1
        radius 0.12
      }
    }
    Emitter {
      name "emitter"
      channel 1
      range 2.0
      baudRate -1
    }
    Receiver {
      name "receiver"
      channel 3
    }
  ]
  name "ROBOT_A"
  controller "<none>"
  physics Physics {
    density -1
    mass 2.0
  }
  boundingObject Cylinder {
    height 0.1
    radius 0.12
  }
}
DEF ROBOT_B Robot {
  translation 2 -2 0.06
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.1 0.9 0.1
        roughness 0.5
        metalness 0
      }
      geometry Cylinder {
        height 0.1
        radius 0.12
      }
    }
    Emitter {
      name "emitter"
      channel 1
      range 2.0
      baudRate -1
    }
    Receiver {
      name "receiver"
      channel 3
    }
  ]
  name "ROBOT_B"
  controller "<none>"
  physics Physics {
    density -1
    mass 2.0
  }
  boundingObject Cylinder {
    height 0.1
    radius 0.12
  }
}
DEF ROBOT_C Robot {
  translation 3 3 0.06
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.1 0.1 0.9
        roughness 0.5
        metalness 0
      }
      geometry Cylinder {
        height 0.1
        radius 0.12
      }
    }
    Emitter {
      name "emitter"
      channel 1
      range 2.0
      baudRate -1
    }
  ]
  name "ROBOT_C"
  controller "<none>"
  physics Physics {
    density -1
    mass 2.0
  }
  boundingObject Cylinder {
    height 0.1
    radius 0.12
  }
}
WORLDEOF

chown ga:ga "$WORLD_FILE"

# Ensure the output file does not pre-exist
rm -f /home/ga/Desktop/warehouse_comms.wbt

# Launch Webots with the broken world
echo "Launching Webots with warehouse_comms_broken.wbt..."
launch_webots_with_world "$WORLD_FILE"

sleep 5

# Focus and maximize window
focus_webots

# Dismiss any potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "World loaded: $WORLD_FILE"
echo "Expected output: /home/ga/Desktop/warehouse_comms.wbt"