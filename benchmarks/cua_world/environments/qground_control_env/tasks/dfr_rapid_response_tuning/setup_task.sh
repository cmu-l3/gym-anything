#!/bin/bash
echo "=== Setting up dfr_rapid_response_tuning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write DFR tuning specifications document
cat > /home/ga/Documents/QGC/dfr_tuning_specs.txt << 'SPECDOC'
DRONE AS A FIRST RESPONDER (DFR) - RAPID RESPONSE TUNING SPEC
Vehicle Class: Interceptor Quadcopter
Deployment: 911 Automated Response
Date: 2026-03-09

=== OVERVIEW ===
Factory defaults limit autonomous flight speeds to ~5 m/s. To meet the 
strict < 90-second response time Service Level Agreement (SLA), the vehicle
must be tuned to maximum safe structural limits. 

=== REQUIRED PARAMETERS ===
Update the following parameters in QGroundControl (Vehicle Setup > Parameters).
CAUTION: The values below are provided in standard metric SI units (m/s). 
The flight controller may expect different units (like cm/s). Look closely at 
the QGroundControl UI unit labels and convert the values before saving.

1. Horizontal Transit Speed (WPNAV_SPEED)
   Required: 22.0 m/s

2. Ascent Speed (WPNAV_SPEED_UP)
   Required: 6.0 m/s

3. Descent Speed (WPNAV_SPEED_DN)
   Required: 4.0 m/s

4. Horizontal Acceleration (WPNAV_ACCEL)
   Required: 3.5 m/s/s

5. Waypoint Turn Radius (WPNAV_RADIUS)
   Required: 8.0 m

6. Final Touchdown Speed (LAND_SPEED)
   Required: 0.8 m/s

=== DELIVERABLE ===
After updating the parameters, write a short text file to:
/home/ga/Documents/QGC/dfr_report.txt

The report must:
1. Confirm that the rapid response tuning is complete.
2. Explicitly state the newly configured horizontal transit speed so dispatchers know the vehicle's top speed.
SPECDOC

chown ga:ga /home/ga/Documents/QGC/dfr_tuning_specs.txt

# 3. Reset target parameters to slow factory defaults
echo "--- Resetting parameters to factory defaults ---"
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
        
        # Reset to slow cinematic defaults
        defaults = {
            b'WPNAV_SPEED': 500.0,
            b'WPNAV_SPEED_UP': 250.0,
            b'WPNAV_SPEED_DN': 150.0,
            b'WPNAV_ACCEL': 100.0,
            b'WPNAV_RADIUS': 200.0,
            b'LAND_SPEED': 50.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to slow defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing report
rm -f /home/ga/Documents/QGC/dfr_report.txt

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

echo "=== dfr_rapid_response_tuning task setup complete ==="