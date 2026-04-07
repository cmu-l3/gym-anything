#!/bin/bash
set -e
echo "=== Setting up compass_orientation_config task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure SITL is running
ensure_sitl_running

# Ensure QGC is running
ensure_qgc_running

# Create the mounting specification sheet
echo "--- Creating mounting specification sheet ---"
SPEC_DIR="/home/ga/Documents/QGC"
mkdir -p "$SPEC_DIR"

cat > "$SPEC_DIR/mounting_spec.txt" << 'SPECEOF'
================================================================================
         AIRFRAME MOUNTING SPECIFICATION — HexDuster-6X (Serial #HD6X-0047)
================================================================================

Prepared by: J. Mendez, Airframe Integration Lead
Date: 2026-03-09
Client: Greenfield AgriServices LLC

SECTION 1: FLIGHT CONTROLLER MOUNTING
--------------------------------------
Flight Controller: Cube Orange (CubePilot)
Mounting Location: Center plate, above spray tank
Physical Rotation: 90° CLOCKWISE from standard nose-forward orientation
  → The USB port faces the LEFT side of the airframe (port side)
  → Standard orientation has USB port facing REARWARD

Required ArduPilot Parameter:
  AHRS_ORIENTATION = 2   (Yaw90 — 90° clockwise rotation)

SECTION 2: EXTERNAL GPS/COMPASS UNIT
--------------------------------------
GPS Unit: CubePilot Here3 (CAN bus)
Mounting: Top of GPS mast, 15 cm above top plate
Physical Rotation: 180° from standard orientation
  → The compass arrow on the Here3 points REARWARD (toward tail)
  → Standard orientation has arrow pointing FORWARD (toward nose)

Required ArduPilot Parameter:
  COMPASS_ORIENT = 4     (Yaw180 — 180° rotation)

SECTION 3: COMPASS CONFIGURATION
--------------------------------------
Due to electromagnetic interference from the 60A spray pump motor mounted
directly below the flight controller, the two internal magnetometers on the
Cube Orange must be DISABLED. Only the external Here3 compass should be used.

Additionally, compass learning must be disabled because we are entering
fixed offsets from the bench calibration performed on 2026-03-08.

Required ArduPilot Parameters:
  COMPASS_EXTERNAL = 1   (Use external compass as primary sensor)
  COMPASS_USE2 = 0       (Disable internal compass #2 — Cube ICM20948)
  COMPASS_USE3 = 0       (Disable internal compass #3 — Cube IST8310)
  COMPASS_LEARN = 0      (Disabled — use fixed offsets from bench cal)

SECTION 4: COMPASS CALIBRATION OFFSETS
--------------------------------------
Bench calibration was performed on 2026-03-08 using a calibrated Helmholtz
coil at the AgriDrone Service Center (Certificate #AC-2026-0891).

Measured compass offsets for external Here3 unit (Compass #1):
  COMPASS_OFS_X = 85     (milliGauss, X-axis offset)
  COMPASS_OFS_Y = -52    (milliGauss, Y-axis offset)

Note: Z-axis offset (COMPASS_OFS_Z) was measured at 0 mGauss and does not
need to be changed from its default value.

================================================================================
SUMMARY OF ALL REQUIRED PARAMETER CHANGES
================================================================================

  Parameter          | Required Value | Notes
  -------------------|---------------|----------------------------------
  AHRS_ORIENTATION   | 2             | Board rotated Yaw90 (90° CW)
  COMPASS_ORIENT     | 4             | External compass Yaw180
  COMPASS_EXTERNAL   | 1             | External compass is primary
  COMPASS_USE2       | 0             | Disable internal compass 2
  COMPASS_USE3       | 0             | Disable internal compass 3
  COMPASS_LEARN      | 0             | Fixed offsets, no learning
  COMPASS_OFS_X      | 85            | X-axis offset (mGauss)
  COMPASS_OFS_Y      | -52           | Y-axis offset (mGauss)

IMPORTANT: Verify all 8 parameters are set correctly before first flight.
           An incorrect AHRS_ORIENTATION will cause the vehicle to fly in
           the wrong direction. Incorrect compass settings will cause
           toilet-bowling or fly-away.

================================================================================
END OF MOUNTING SPECIFICATION
================================================================================
SPECEOF

chown -R ga:ga "$SPEC_DIR"
echo "Mounting spec created at $SPEC_DIR/mounting_spec.txt"

# Reset all 8 target parameters to factory defaults via pymavlink
# This guarantees that a "do-nothing" agent gets 0 points.
echo "--- Resetting parameters to defaults ---"
cat > /tmp/reset_params.py << 'PYEOF'
import sys, time
sys.path.insert(0, "/opt/ardupilot")
try:
    from pymavlink import mavutil
    print("Connecting to SITL...")
    mav = mavutil.mavlink_connection("tcp:127.0.0.1:5762", source_system=254, dialect='ardupilotmega')
    mav.wait_heartbeat(timeout=30)
    print(f"Connected: system {mav.target_system}, component {mav.target_component}")
    time.sleep(2) # Stabilize

    defaults = {
        b'AHRS_ORIENTATION': 0.0,
        b'COMPASS_ORIENT': 0.0,
        b'COMPASS_EXTERNAL': 0.0,
        b'COMPASS_USE2': 1.0,
        b'COMPASS_USE3': 1.0,
        b'COMPASS_LEARN': 3.0,
        b'COMPASS_OFS_X': 0.0,
        b'COMPASS_OFS_Y': 0.0,
    }

    for param_name, default_val in defaults.items():
        print(f"  Resetting {param_name.decode()} -> {default_val}")
        mav.mav.param_set_send(
            mav.target_system,
            mav.target_component,
            param_name,
            float(default_val),
            mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
        )
        time.sleep(0.3)

    print("All parameters reset to defaults.")
    mav.close()
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

su - ga -c "python3 /tmp/reset_params.py"

# Focus and maximize QGC, then dismiss dialogs
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Parameters reset to defaults, mounting spec ready."