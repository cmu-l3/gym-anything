#!/bin/bash
echo "=== Setting up configure_satellite_reaction_wheels task ==="

source /workspace/scripts/task_utils.sh

# Detect Webots installation
WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 2

# Create the base world file with "Earth" defaults (wrong config)
USER_WORLD="/home/ga/webots_projects/cubesat_adcs.wbt"
mkdir -p /home/ga/webots_projects

cat > "$USER_WORLD" << 'EOF'
#VRML_SIM R2023b utf8
WorldInfo {
  basicTimeStep 16
  gravity 0 -9.81 0
}
Viewpoint {
  orientation -0.15 0.95 0.25 1.15
  position 1.2 1.0 1.2
}
TexturedBackground {
}
TexturedBackgroundLight {
}
DEF CUBESAT Robot {
  translation 0 0.5 0
  children [
    Shape {
      appearance PBRAppearance {
        baseColor 0.8 0.8 0.8
        roughness 0.5
        metalness 0.8
      }
      geometry Box {
        size 0.2 0.2 0.2
      }
    }
    DEF YAW_WHEEL HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 1 0
      }
      device [
        RotationalMotor {
          name "yaw_motor"
          maxVelocity 10
          maxTorque 10
        }
      ]
      endPoint Solid {
        physics Physics {
          mass 1.0
        }
      }
    }
    DEF PITCH_WHEEL HingeJoint {
      jointParameters HingeJointParameters {
        axis 1 0 0
      }
      device [
        RotationalMotor {
          name "pitch_motor"
          maxVelocity 10
          maxTorque 10
        }
      ]
      endPoint Solid {
        physics Physics {
          mass 1.0
        }
      }
    }
    DEF ROLL_WHEEL HingeJoint {
      jointParameters HingeJointParameters {
        axis 0 0 1
      }
      device [
        RotationalMotor {
          name "roll_motor"
          maxVelocity 10
          maxTorque 10
        }
      ]
      endPoint Solid {
        physics Physics {
          mass 1.0
        }
      }
    }
  ]
  name "cubesat"
  physics Physics {
    density -1
    mass 1.33
  }
}
EOF

chown -R ga:ga /home/ga/webots_projects

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous output file
rm -f /home/ga/Desktop/cubesat_adcs_configured.wbt

# Launch Webots with the cubesat world
echo "Launching Webots with CubeSat world..."
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
echo "  1. Set gravity to 0 0 0"
echo "  2. Add Damping node to CUBESAT physics and set linear/angular to 0.0"
echo "  3. Modify ALL THREE wheels: maxVelocity=600, maxTorque=0.05, mass=0.12"
echo "  4. Save to /home/ga/Desktop/cubesat_adcs_configured.wbt"