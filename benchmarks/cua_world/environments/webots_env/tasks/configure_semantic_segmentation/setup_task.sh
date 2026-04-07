#!/bin/bash
echo "=== Setting up Semantic Segmentation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/webots_projects
mkdir -p /home/ga/Desktop

# Programmatically generate the starting world file to ensure a clean state
WORLD_FILE="/home/ga/webots_projects/warehouse_synthetic_gen.wbt"
cat > "$WORLD_FILE" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
}
Viewpoint {
  orientation -0.2 0.9 0.3 1.2
  position 3.0 2.5 3.0
}
TexturedBackground {}
TexturedBackgroundLight {}
RectangleArena {
  floorSize 5 5
}
DEF WAREHOUSE_ROBOT Robot {
  translation 0 0.1 0
  children [
    Camera {
      translation 0 0.2 0
      name "vision_sensor"
      width 640
      height 480
    }
  ]
}
DEF HAZMAT_BARREL Solid {
  translation 1 0.3 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.1
      }
      geometry Cylinder {
        height 0.6
        radius 0.2
      }
    }
  ]
  boundingObject Cylinder {
    height 0.6
    radius 0.2
  }
}
DEF SHIPPING_CRATE Solid {
  translation -1 0.2 1
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.5 0.3 0.1
      }
      geometry Box {
        size 0.4 0.4 0.4
      }
    }
  ]
  boundingObject Box {
    size 0.4 0.4 0.4
  }
}
EOF

# Ensure appropriate permissions
chown -R ga:ga /home/ga/webots_projects
chown ga:ga /home/ga/Desktop
rm -f /home/ga/Desktop/semantic_dataset_configured.wbt

# Launch Webots with the synthetic generation scenario
echo "Launching Webots with warehouse synthetic generation world..."
launch_webots_with_world "$WORLD_FILE"

sleep 5

# Focus and maximize the window for the agent
focus_webots

# Dismiss any stray dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Capture initial evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $WORLD_FILE"
echo "Agent should:"
echo "  1. Add Recognition node to Camera 'vision_sensor'."
echo "  2. Set segmentation=TRUE and maxRange=15.0."
echo "  3. Set HAZMAT_BARREL recognitionColors to [ 1 0 0 ]."
echo "  4. Set SHIPPING_CRATE recognitionColors to [ 0 0 1 ]."
echo "  5. Save modified world to: /home/ga/Desktop/semantic_dataset_configured.wbt"