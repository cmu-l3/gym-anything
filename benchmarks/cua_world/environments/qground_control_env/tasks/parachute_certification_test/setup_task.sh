#!/bin/bash
echo "=== Setting up parachute_certification_test task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the certification specification document
cat > /home/ga/Documents/QGC/parachute_spec.txt << 'SPECDOC'
UAV PARACHUTE RECOVERY SYSTEM - CERTIFICATION SPECIFICATION
Reference: EASA SORA / FAA FTS Waiver Requirements
Date: 2026-03-10

=== PART 1: FLIGHT CONTROLLER PARAMETERS ===
The vehicle is equipped with a servo-released parachute mechanism on Auxiliary Channel 1 (SERVO9). 
You must configure the following 4 parameters in Vehicle Setup > Parameters:

  1. CHUTE_ENABLED = 1
     (Enables the parachute subsystem. Default is 0.)
     
  2. CHUTE_TYPE = 10
     (Specifies the release mechanism. 10 = Servo. Default is 0.)
     
  3. SERVO9_FUNCTION = 27
     (Maps Auxiliary Channel 1 to the parachute release trigger. Default is 0.)
     
  4. CHUTE_ALT_MIN = 25
     (Minimum altitude in meters for deployment to ensure canopy inflation. Default is 10.)

=== PART 2: FLIGHT TEST MISSION PLAN ===
To certify the system, you must create a mission plan to autonomously trigger the parachute over a secure drop zone. 

Using QGroundControl's Plan View, create a mission with this exact sequence:
  Item 1: Takeoff
          - Altitude: 80 meters
          
  Item 2: Waypoint (The Drop Zone)
          - Latitude: -35.3615
          - Longitude: 149.1650
          - Altitude: 80 meters
          
  Item 3: Do Parachute
          - Action: Release / Trigger

Save the mission plan file to:
  /home/ga/Documents/QGC/parachute_test.plan

Do not arm or fly the vehicle. Just save the configurations and the plan file.
SPECDOC

chown ga:ga /home/ga/Documents/QGC/parachute_spec.txt

# 3. Reset parameters via pymavlink so do-nothing = 0 points
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
        # Reset to known defaults that differ from required values
        defaults = {
            b'CHUTE_ENABLED': 0.0,
            b'CHUTE_TYPE': 0.0,
            b'SERVO9_FUNCTION': 0.0,
            b'CHUTE_ALT_MIN': 10.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Clean up any existing result file
rm -f /home/ga/Documents/QGC/parachute_test.plan

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL and QGC are running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus, maximize, and dismiss dialogs
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== parachute_certification_test task setup complete ==="
echo "Spec file: /home/ga/Documents/QGC/parachute_spec.txt"