#!/bin/bash
echo "=== Setting up urban_flight_safety_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the operations brief that the agent must read
cat > /home/ga/Documents/QGC/urban_ops_brief.txt << 'OPDOC'
=========================================================
  URBAN OPERATIONS BRIEF: ZURICH ROOFTOP DELIVERY
  Date: 2026-03-10
  Prepared by: Compliance & Safety Dept.
=========================================================

ENVIRONMENT HAZARD:
Target landing zone is a commercial rooftop containing heavy HVAC 
machinery and steel reinforced concrete. Extreme magnetic interference 
is expected. Urban canyon effects may degrade GPS multipath.

REQUIRED CONFIGURATION CHANGES:

1. GPS Quality Enforcements
   - To prevent multipath errors, increase the minimum required 
     satellites for arming (GPS_SATS_MIN) to 12.
   - Tighten the acceptable HDOP threshold (GPS_HDOP_GOOD) to 1.00 
     (Value entered as 100).

2. Magnetic Interference Mitigation
   - Disable all magnetometers entirely to prevent flyaways. 
     Set COMPASS_USE, COMPASS_USE2, and COMPASS_USE3 to 0.

3. Heading / Yaw Source
   - Because the compass is disabled, the EKF must rely on GPS 
     kinematics for heading. Set EK3_SRC1_YAW to 2.

4. Ground Safety
   - To prevent wind-induced tip-overs after touching down on the 
     rooftop, the vehicle must disarm quickly. Reduce the auto-disarm 
     delay (DISARM_DELAY) to 5 seconds.

INSTRUCTIONS:
Open QGroundControl, go to Vehicle Setup > Parameters, search for each 
variable, and set it to the requested value. The changes are sent to 
the drone immediately.
OPDOC

chown ga:ga /home/ga/Documents/QGC/urban_ops_brief.txt

# 3. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target parameters to defaults to ensure a strict baseline
# This guarantees that do-nothing agent gets 0 points.
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
        
        # Reset to ArduCopter factory defaults
        defaults = {
            b'GPS_SATS_MIN': 6.0,
            b'GPS_HDOP_GOOD': 140.0,
            b'COMPASS_USE': 1.0,
            b'COMPASS_USE2': 1.0,
            b'COMPASS_USE3': 1.0,
            b'EK3_SRC1_YAW': 1.0,
            b'DISARM_DELAY': 10.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters successfully reset to baseline defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== urban_flight_safety_config task setup complete ==="
echo "Operations Brief: /home/ga/Documents/QGC/urban_ops_brief.txt"