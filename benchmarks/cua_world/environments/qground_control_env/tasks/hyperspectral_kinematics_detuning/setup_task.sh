#!/bin/bash
echo "=== Setting up hyperspectral_kinematics_detuning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the integration manual (Agent must read this to get the constraints)
cat > /home/ga/Documents/QGC/hyperspectral_integration.txt << 'MANUALDOC'
RESONON PIKA L - PUSH-BROOM HYPERSPECTRAL SCANNER
UAV Integration & Flight Constraints Manual
Date: 2026-03-09

=== CRITICAL FLIGHT KINEMATICS LIMITS ===
Push-broom sensors require extremely smooth, slow, and level flight to 
avoid dropping pixel lines or introducing severe "wobble" distortion.
The default drone parameters are far too aggressive. 

You MUST configure the drone's autonomous waypoint navigation parameters 
so they do NOT exceed the following physical constraints:

1. Maximum Vehicle Tilt Angle: 15 degrees
   (The gimbal cannot compensate for tilt beyond 15 deg. Set ANGLE_MAX accordingly.)

2. Auto Flight Speed: 3.0 meters/second
   (Faster speeds will stretch the data pixels along the flight track.)

3. Auto Horizontal Acceleration: 1.0 meters/second²
   (Prevents violent jerks when starting/stopping at waypoints.)

4. Auto Vertical Acceleration: 0.5 meters/second²
   (Prevents altitude bounce when entering a survey line.)

5. Climb Speed: 1.5 meters/second
   (Gentle ascent to survey altitude.)

6. Descent Speed: 1.0 meters/second
   (Gentle descent to prevent jarring the optics.)

=== REQUIRED ACTIONS ===
Convert the above physical values into ArduPilot's internal parameter units 
(e.g., cm/s, cm/s/s, centidegrees). Use QGroundControl's Vehicle Setup > Parameters 
menu to update the following parameters:
- ANGLE_MAX
- WPNAV_SPEED
- WPNAV_ACCEL
- WPNAV_ACCEL_Z
- WPNAV_SPEED_UP
- WPNAV_SPEED_DN

After setting the parameters, you must create a sign-off report at:
/home/ga/Documents/QGC/integration_signoff.txt
MANUALDOC

chown ga:ga /home/ga/Documents/QGC/hyperspectral_integration.txt

# 3. Ensure no sign-off file exists beforehand
rm -f /home/ga/Documents/QGC/integration_signoff.txt

# 4. Reset target parameters to aggressive factory defaults (so do-nothing = 0 pts)
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # warm-up
        # Reset to very aggressive defaults, far from the hyperspectral requirements
        defaults = {
            b'ANGLE_MAX': 3000.0,       # 30 deg
            b'WPNAV_SPEED': 1000.0,     # 10 m/s
            b'WPNAV_ACCEL': 250.0,      # 2.5 m/s/s
            b'WPNAV_ACCEL_Z': 100.0,    # 1.0 m/s/s
            b'WPNAV_SPEED_UP': 250.0,   # 2.5 m/s
            b'WPNAV_SPEED_DN': 150.0,   # 1.5 m/s
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to aggressive defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

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

echo "=== hyperspectral_kinematics_detuning task setup complete ==="
echo "Manual: /home/ga/Documents/QGC/hyperspectral_integration.txt"