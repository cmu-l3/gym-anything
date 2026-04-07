#!/bin/bash
echo "=== Setting up wildlife_silent_flight_tuning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write biological operations memo
cat > /home/ga/Documents/QGC/silent_flight_memo.txt << 'MEMODOC'
MEMORANDUM
To: UAV Operations Team
From: Dr. Sarah Jenkins, Lead Wildlife Biologist
Date: 2026-03-10
Subject: Acoustic Mitigation Parameters for Nesting Season

To comply with our USFW permit for the eagle monitoring project, the Alta-X quadcopter must be tuned to minimize rotor tip noise. We achieve this by restricting the maximum allowed motor RPM and smoothing out all angular accelerations to prevent sudden motor revving.

Please apply the following parameter changes in QGroundControl immediately:

- Max Motor Spin (MOT_SPIN_MAX): 0.80
- Max Pitch Acceleration (ATC_ACCEL_P_MAX): 40000
- Max Roll Acceleration (ATC_ACCEL_R_MAX): 40000
- Max Yaw Acceleration (ATC_ACCEL_Y_MAX): 15000
- Waypoint Acceleration (WPNAV_ACCEL): 100
- Maximum Lean Angle (ANGLE_MAX): 2500

To set these:
1. Open QGroundControl and go to Vehicle Setup (the "Q" or Gear icon).
2. Select "Parameters".
3. Search for each parameter exactly as named above.
4. Update the value and save.

Do not dispatch the vehicle until all 6 parameters are verified.
MEMODOC

chown ga:ga /home/ga/Documents/QGC/silent_flight_memo.txt

# 3. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target parameters to aggressive/loud defaults
# This ensures that a "do-nothing" strategy scores exactly 0 points.
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
        
        # Reset to known aggressive defaults that drastically differ from required values
        defaults = {
            b'MOT_SPIN_MAX': 0.95,
            b'ATC_ACCEL_P_MAX': 110000.0,
            b'ATC_ACCEL_R_MAX': 110000.0,
            b'ATC_ACCEL_Y_MAX': 27000.0,
            b'WPNAV_ACCEL': 250.0,
            b'ANGLE_MAX': 4500.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to loud/aggressive factory defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== wildlife_silent_flight_tuning task setup complete ==="
echo "Memo: /home/ga/Documents/QGC/silent_flight_memo.txt"