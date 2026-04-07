#!/bin/bash
echo "=== Setting up autotune_heavylift_prep task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write tuning specification document
cat > /home/ga/Documents/QGC/autotune_spec.txt << 'SPECDOC'
FLIGHT TEST: HEAVY-LIFT AUTOTUNE PREPARATION
Vehicle ID: HL-1200-X8
Date: 2026-03-10
Engineer: Lead Flight Dynamics Test Engineer

WARNING: This vehicle utilizes 24-inch propellers. Running AutoTune with the 
factory default aggressiveness (0.1) or default filter bandwidths (20Hz/40Hz) 
will induce catastrophic structural resonance and potential motor mount failure.

=== REQUIRED PRE-FLIGHT PARAMETERS ===

Before the test pilot takes off, you must use QGroundControl (Vehicle Setup > Parameters) 
to set the following 6 parameters to the values specified below:

1. AUTOTUNE_AGGR
   Required Value: 0.05
   Reason: Reduces tuning aggressiveness to 5% to prevent heavy prop desync.

2. AUTOTUNE_AXES
   Required Value: 3
   Reason: Bitmask 3 enables Roll (1) and Pitch (2) only. Yaw tuning is disabled.

3. RC7_OPTION
   Required Value: 17
   Reason: Maps the AutoTune trigger to RC Channel 7.

4. ATC_RAT_RLL_FLTT
   Required Value: 10
   Reason: Lowers the Roll target filter to 10 Hz for large frame inertia.

5. ATC_RAT_PIT_FLTT
   Required Value: 10
   Reason: Lowers the Pitch target filter to 10 Hz for large frame inertia.

6. INS_GYRO_FILTER
   Required Value: 20
   Reason: Lowers the primary gyro hardware filter to 20 Hz to reject frame resonance.

Please confirm all 6 parameters are written to the flight controller before dispatching the vehicle.
SPECDOC

chown ga:ga /home/ga/Documents/QGC/autotune_spec.txt

# 3. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset flight controller parameters to dangerous factory defaults 
# This ensures that "do nothing" scores 0 points.
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # warm-up: let MAVLink channel stabilize
        
        # Reset parameters to dangerous defaults (what a generic 400mm quad would use)
        defaults = {
            b'AUTOTUNE_AGGR': 0.1,
            b'AUTOTUNE_AXES': 7.0,
            b'RC7_OPTION': 0.0,
            b'ATC_RAT_RLL_FLTT': 20.0,
            b'ATC_RAT_PIT_FLTT': 20.0,
            b'INS_GYRO_FILTER': 40.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== autotune_heavylift_prep task setup complete ==="
echo "Spec Document: /home/ga/Documents/QGC/autotune_spec.txt"