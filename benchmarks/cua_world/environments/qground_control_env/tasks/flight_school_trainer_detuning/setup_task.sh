#!/bin/bash
echo "=== Setting up flight_school_trainer_detuning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write SOP document
cat > /home/ga/Documents/QGC/training_limits.txt << 'EOF'
FLIGHT ACADEMY SOP: NOVICE TRAINER DETUNING
Target: AC-TRAINER-01

The factory default ArduCopter is too aggressive for Day-1 students.
Set the following 6 parameters to restrict the flight envelope:

1. ANGLE_MAX      -> 1500  (Limits bank angle to 15 degrees. Default is 4500)
2. PILOT_SPEED_UP -> 100   (Limits manual climb to 1 m/s. Default is 250)
3. PILOT_SPEED_DN -> 100   (Limits manual descent to 1 m/s. Default is 150)
4. LOIT_SPEED     -> 200   (Limits loiter horizontal speed to 2 m/s. Default is 1250)
5. LOIT_ACC_MAX   -> 100   (Softens loiter acceleration. Default is 500)
6. PILOT_Y_RATE   -> 90    (Limits manual yaw rotation rate. Default is 202)

INSTRUCTIONS:
1. Open QGroundControl -> Vehicle Setup (Gear icon) -> Parameters.
2. Search for and change all 6 parameters above.
3. Once all parameters are set, click the "Tools" button in the top right of the Parameters screen.
4. Click "Save to file".
5. Save the configuration to: /home/ga/Documents/QGC/novice_profile.params
EOF
chown ga:ga /home/ga/Documents/QGC/training_limits.txt

# 3. Reset target parameters to defaults to ensure doing nothing scores 0 pts
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # Wait for connection stability
        
        defaults = {
            b'ANGLE_MAX': 4500.0,
            b'PILOT_SPEED_UP': 250.0,
            b'PILOT_SPEED_DN': 150.0,
            b'LOIT_SPEED': 1250.0,
            b'LOIT_ACC_MAX': 500.0,
            b'PILOT_Y_RATE': 202.0
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# Ensure no old profile file exists
rm -f /home/ga/Documents/QGC/novice_profile.params

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Ensure SITL and QGC running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus, maximize, and prep UI
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Initial evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== flight_school_trainer_detuning task setup complete ==="
echo "SOP: /home/ga/Documents/QGC/training_limits.txt"