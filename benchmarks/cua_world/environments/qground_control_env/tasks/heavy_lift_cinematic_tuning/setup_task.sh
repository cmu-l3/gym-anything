#!/bin/bash
echo "=== Setting up heavy_lift_cinematic_tuning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write cinematic tuning specifications
cat > /home/ga/Documents/QGC/cinematic_tuning_specs.txt << 'SPECDOC'
CINEMATIC TUNING SPECIFICATIONS
Vehicle: Heavy-Lift Hexacopter (Cinema Rig)
Role: Camera Operator
Date: 2026-03-10

=== REQUIRED PARAMETER CHANGES ===
The following 6 parameters must be set in Vehicle Setup > Parameters to soften flight dynamics for smooth camera tracking:

1. Waypoint Speed (WPNAV_SPEED): 350
   (Default 500 cm/s is too fast for tracking. Reduce to 350 cm/s)

2. Waypoint Acceleration (WPNAV_ACCEL): 80
   (Default 100 cm/s/s causes jerky starts/stops. Reduce to 80 cm/s/s)

3. Waypoint Radius (WPNAV_RADIUS): 600
   (Default 200 cm causes sharp corners. Increase to 600 cm for smooth curves)

4. Waypoint Yaw Behavior (WP_YAW_BEHAVIOR): 0
   (Default 2 points drone at next waypoint. Set to 0 to NEVER change yaw automatically. The camera operator will control yaw manually.)

5. Yaw Acceleration Max (ATC_ACCEL_Y_MAX): 9000
   (Default 27000 cd/s/s causes snappy yaw. Reduce to 9000)

6. Pilot Yaw Rate (PILOT_Y_RATE): 45
   (Default 202.5 deg/s is too sensitive for joystick panning. Reduce to 45 deg/s)

=== TEST FLIGHT PLAN ===
Create a test mission in Plan View with:
- Takeoff command
- 4 Navigation Waypoints (arranged in a polygon/square)
- RTL command at the end
Save to: /home/ga/Documents/QGC/cinematic_test.plan

=== SIGNOFF ===
Create a text file at /home/ga/Documents/QGC/tuning_signoff.txt
It must contain the word "cinematic" and confirm setup is complete.
SPECDOC

chown ga:ga /home/ga/Documents/QGC/cinematic_tuning_specs.txt

# 3. Reset parameters to ArduPilot defaults so do-nothing fails
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
        defaults = {
            b'WPNAV_SPEED': 500.0,
            b'WPNAV_ACCEL': 100.0,
            b'WPNAV_RADIUS': 200.0,
            b'WP_YAW_BEHAVIOR': 2.0,
            b'ATC_ACCEL_Y_MAX': 27000.0,
            b'PILOT_Y_RATE': 202.5,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# Clean any existing output files
rm -f /home/ga/Documents/QGC/cinematic_test.plan
rm -f /home/ga/Documents/QGC/tuning_signoff.txt

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Check and ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Check and ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus, maximize, take screenshot
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

take_screenshot /tmp/task_start_screenshot.png

echo "=== setup complete ==="