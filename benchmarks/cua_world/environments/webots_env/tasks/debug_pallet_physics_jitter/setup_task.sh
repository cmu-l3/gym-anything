#!/bin/bash
echo "=== Setting up debug_pallet_physics_jitter task ==="

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

mkdir -p /home/ga/webots_projects
USER_WORLD="/home/ga/webots_projects/palletizer_unstable.wbt"
OUTPUT_WORLD="/home/ga/Desktop/stabilized_pallet.wbt"

# Generate the unstable palletizer world dynamically
echo "Generating unstable palletizer world..."
python3 << EOF
with open('$USER_WORLD', 'w') as f:
    f.write('''#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  cfm 0.00001
  erp 0.2
  contactProperties [
    ContactProperties {
      material1 "cardboard"
      material2 "cardboard"
      coulombFriction [ 0.5 ]
      softCFM 0.0
    }
  ]
}
Viewpoint {
  orientation -0.15 0.96 0.2 1.3
  position 3.5 2.5 3.5
}
TexturedBackground {
}
TexturedBackgroundLight {
}
Solid {
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.6 0.6 0.6
        roughness 1
        metalness 0
      }
      geometry DEF FLOOR Plane {
        size 10 10
      }
    }
  ]
  contactMaterial "default"
  boundingObject USE FLOOR
  locked TRUE
}
''')

    # Add a tall stack of boxes to induce jitter/instability
    for i in range(12):
        y = 0.1 + i * 0.201  # Slight gap to encourage settling/jitter
        f.write(f'''
Solid {{
  translation 0 {y} 0
  children [
    Shape {{
      appearance PBRAppearance {{
        baseColor 0.8 0.6 0.4
        roughness 0.9
      }}
      geometry DEF BOX Box {{
        size 0.4 0.2 0.4
      }}
    }}
  ]
  contactMaterial "cardboard"
  boundingObject USE BOX
  physics Physics {{
    mass 5.0
  }}
}}
''')
EOF

chown ga:ga "$USER_WORLD"

# Record timestamp for anti-gaming (ensure output file is created *after* task start)
date +%s > /tmp/task_start_time.txt

# Create Desktop directory if needed and clean up previous attempts
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop
rm -f "$OUTPUT_WORLD"

# Launch Webots with the generated scenario
echo "Launching Webots with palletizer scenario world..."
launch_webots_with_world "$USER_WORLD"

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing the unstable stack
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "World loaded: $USER_WORLD"
echo "Agent should stabilize physics and save to: $OUTPUT_WORLD"