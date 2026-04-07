#!/bin/bash
echo "=== Setting up tactical_throw_deployment_setup task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the tactical operations brief
cat > /home/ga/Documents/QGC/tactical_brief.txt << 'BRIEFDOC'
TACTICAL UAS DEPLOYMENT BRIEF
===================================================
Airframe ID: TAC-UAV-09
Mission: Vertical Roof Drop Insertion
Date: 2026-03-10
===================================================

SITUATION:
The drone will be deployed by a tactical operator dropping it through a roof vent. 
To maintain stealth and safety, the propellers MUST NOT spin while the operator 
holds the armed drone. It must detect the drop, start its motors in mid-air, 
and recover into a stable GPS hover.

REQUIRED PARAMETER CONFIGURATION:
You must use QGroundControl (Vehicle Setup > Parameters) to configure the 
following 6 parameters precisely. 

1. Flight Mode 1 (FLTMODE1)
   Set to: 18 (Throw Mode)
   Reason: Maps the primary switch to the throw/drop deployment mode.

2. Throw Type (THROW_TYPE)
   Set to: 1 (Downward Drop)
   Reason: Tells the flight controller to expect a drop instead of an upward throw.

3. Next Mode after Throw (THROW_NEXTMODE)
   Set to: 5 (Loiter)
   Reason: Ensures the drone enters a GPS-assisted hover after recovering from the drop.

4. Throw Motor Start (THROW_MOT_START)
   Set to: 1 (Start immediately)
   Reason: Motors must spin up the instant free-fall is detected.

5. Motor Spin when Armed (MOT_SPIN_ARM)
   Set to: 0.0 (No spin)
   Reason: CRITICAL SAFETY. Propellers must remain completely still while armed in the operator's hand.

6. Auto-Disarm Delay (DISARM_DELAY)
   Set to: 0 (Disabled)
   Reason: The operator may hold the armed drone for an extended period waiting for the breach command. The drone must not automatically disarm itself.

SIGN-OFF PROCEDURE:
After setting ALL 6 parameters in QGroundControl, create a text file at:
/home/ga/Documents/QGC/ready_signoff.txt

The file must contain:
- The Airframe ID (TAC-UAV-09)
- Your name/initials
- The exact statement: "Throw mode configured"
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/tactical_brief.txt

# 3. Reset parameters to defaults to ensure a clean starting slate (prevents gaming)
# Default values deliberately fail the verification checks.
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
        
        defaults = {
            b'FLTMODE1': 0.0,          # Stabilize
            b'THROW_TYPE': 0.0,        # Upward throw
            b'THROW_NEXTMODE': 0.0,    # Stabilize
            b'THROW_MOT_START': 0.0,   # Wait for apex
            b'MOT_SPIN_ARM': 0.1,      # Spin slow
            b'DISARM_DELAY': 10.0,     # 10s auto-disarm
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults (unsafe for throw).")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing sign-off report
rm -f /home/ga/Documents/QGC/ready_signoff.txt

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 7. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== tactical_throw_deployment_setup task setup complete ==="