#!/bin/bash
echo "=== Setting up LiDAR Payload Nav Tuning task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the payload integration specification
echo "--- Creating payload integration spec ---"
SPEC_DIR="/home/ga/Documents/QGC"
mkdir -p "$SPEC_DIR"

cat > "$SPEC_DIR/lidar_payload_spec.txt" << 'SPEC'
=======================================================================
  PAYLOAD INTEGRATION SPECIFICATION — Velodyne Puck LITE (VLP-16)
  Platform: S900 Hexacopter  |  Payload Mass: 1.8 kg
  Document: PIS-2024-0147    |  Revision: C
  Prepared by: Flight Operations Engineering
=======================================================================

SECTION 4: NAVIGATION PARAMETER MODIFICATIONS

The following ArduPilot parameters MUST be changed from factory defaults
before any LiDAR mapping flight with this payload installed. Failure to
apply these settings will result in point cloud smearing at waypoint
transitions and potential IMU saturation during aggressive maneuvers.

  ┌──────────────────┬───────────┬─────────────────────────────────────┐
  │ Parameter        │ Set Value │ Rationale                           │
  ├──────────────────┼───────────┼─────────────────────────────────────┤
  │ WPNAV_SPEED      │ 800       │ 8 m/s cruise for mapping passes;    │
  │                  │           │ balances coverage rate vs. point    │
  │                  │           │ density at 10 Hz scan rate          │
  ├──────────────────┼───────────┼─────────────────────────────────────┤
  │ WPNAV_SPEED_UP   │ 150       │ Reduced from 250 default; heavy     │
  │                  │           │ payload draws excessive current on  │
  │                  │           │ fast climbs and causes vibe spikes  │
  ├──────────────────┼───────────┼─────────────────────────────────────┤
  │ WPNAV_SPEED_DN   │ 100       │ Gentle descent prevents vortex ring │
  │                  │           │ state onset with increased disk     │
  │                  │           │ loading; also reduces LiDAR return  │
  │                  │           │ distortion from vertical velocity   │
  ├──────────────────┼───────────┼─────────────────────────────────────┤
  │ WPNAV_ACCEL      │ 200       │ Moderate horizontal acceleration;   │
  │                  │           │ prevents attitude transients >15°   │
  │                  │           │ that saturate the IMU's ±16g range  │
  ├──────────────────┼───────────┼─────────────────────────────────────┤
  │ WPNAV_RADIUS     │ 300       │ 3 m acceptance radius; allows       │
  │                  │           │ smoother line-to-line transitions   │
  │                  │           │ at survey turnarounds, reducing     │
  │                  │           │ attitude oscillation during turns   │
  ├──────────────────┼───────────┼─────────────────────────────────────┤
  │ LOIT_SPEED       │ 800       │ Reduced loiter speed for hover-scan │
  │                  │           │ operations over structures; matches │
  │                  │           │ cruise speed for consistency        │
  ├──────────────────┼───────────┼─────────────────────────────────────┤
  │ RTL_SPEED        │ 500       │ Dedicated 5 m/s return speed;       │
  │                  │           │ default=0 inherits WPNAV_SPEED      │
  │                  │           │ which is too fast for return with   │
  │                  │           │ potentially depleted battery        │
  └──────────────────┴───────────┴─────────────────────────────────────┘

  NOTE: All values are in ArduPilot native units (cm/s, cm/s², cm).
        Changes take effect immediately — no reboot required.

SECTION 5: POST-CONFIGURATION VERIFICATION

After setting parameters, verify values by re-reading each parameter
in the Parameters page. Do NOT arm the vehicle until all 7 parameters
are confirmed correct.
=======================================================================
SPEC

chown ga:ga "$SPEC_DIR/lidar_payload_spec.txt"
echo "Payload spec created at $SPEC_DIR/lidar_payload_spec.txt"

# 2. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 3. Reset all 7 parameters to factory defaults via pymavlink
echo "--- Resetting navigation parameters to factory defaults ---"
# Wait for SITL TCP port to be available
for i in {1..30}; do
    if nc -z 127.0.0.1 5762 2>/dev/null; then
        break
    fi
    sleep 1
done

python3 << 'PYEOF'
import sys
import time

try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:127.0.0.1:5762', source_system=254)
    msg = master.wait_heartbeat(timeout=30)
    if not msg:
        print("ERROR: No heartbeat received from SITL")
        sys.exit(1)
        
    sysid = master.target_system
    compid = master.target_component
    time.sleep(1) # Allow connection to stabilize

    # Factory defaults for the 7 parameters
    defaults = {
        b'WPNAV_SPEED': 500.0,
        b'WPNAV_SPEED_UP': 250.0,
        b'WPNAV_SPEED_DN': 150.0,
        b'WPNAV_ACCEL': 100.0,
        b'WPNAV_RADIUS': 200.0,
        b'LOIT_SPEED': 1250.0,
        b'RTL_SPEED': 0.0,
    }

    for param_name, default_val in defaults.items():
        master.mav.param_set_send(
            sysid, compid,
            param_name,
            default_val,
            mavutil.mavlink.MAV_PARAM_TYPE_REAL32
        )
        time.sleep(0.3)
    
    print("All parameters reset to factory defaults")

except Exception as e:
    print(f"ERROR resetting parameters: {e}")
PYEOF

# 4. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running
sleep 3
maximize_qgc
dismiss_dialogs

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== LiDAR Payload Nav Tuning task setup complete ==="