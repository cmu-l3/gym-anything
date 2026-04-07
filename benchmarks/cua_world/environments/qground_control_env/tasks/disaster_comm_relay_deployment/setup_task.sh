#!/bin/bash
echo "=== Setting up disaster_comm_relay_deployment task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the deployment brief
cat > /home/ga/Documents/QGC/relay_deployment_brief.txt << 'BRIEFDOC'
DISASTER RESPONSE: COMM RELAY DEPLOYMENT BRIEF
Operation: Post-Hurricane Cellular Restoration (Sector 4)
Vehicle: Heavy-Lift Hexacopter (AC-SITL-Relay)
Date: 2026-03-09

=== 1. FAILSAFE OVERRIDES (CRITICAL) ===
Because this drone IS the network, we expect our own ground control station 
connection might drop. The drone MUST NOT abandon its post if this happens.
Standard failsafes are currently set to Return-to-Launch (0 or 1). 

You must change these parameters in Vehicle Setup > Parameters:
  - FS_THR_ENABLE = 2 (Continue with mission in Auto mode)
  - FS_GCS_ENABLE = 2 (Continue with mission in Auto mode)

=== 2. RELAY MISSION PLAN ===
Create a mission plan with the following sequence:

  A. Takeoff
  B. Fly to the relay holding point (Waypoint):
     - Latitude: -35.3580
     - Longitude: 149.1660
     - Altitude: 110 m
  C. Point the directional backhaul antenna at the mainland macro-cell:
     - Use the "Change Heading" (Condition Yaw) command
     - Target Heading: 245 degrees
  D. Hold position and broadcast:
     - Use the "Loiter (Time)" command
     - Duration: 3600 seconds (1 hour)
  E. Return to Launch (RTL) at the end of the loiter.

=== 3. EXPORT ===
Save the completed mission plan to:
/home/ga/Documents/QGC/comm_relay.plan
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/relay_deployment_brief.txt

# 3. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target failsafes to defaults (RTL/Disabled) so do-nothing = 0 pts
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)
        # Reset to known unsafe/default values that differ from required (2)
        defaults = {
            b'FS_THR_ENABLE': 1.0,
            b'FS_GCS_ENABLE': 1.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults")
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

# 7. Focus, maximize, and cleanup UI
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== disaster_comm_relay_deployment task setup complete ==="
echo "Brief: /home/ga/Documents/QGC/relay_deployment_brief.txt"