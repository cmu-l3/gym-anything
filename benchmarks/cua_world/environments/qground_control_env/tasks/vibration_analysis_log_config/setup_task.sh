#!/bin/bash
echo "=== Setting up vibration_analysis_log_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the service bulletin document
cat > /home/ga/Documents/QGC/vibration_test_bulletin.txt << 'EOF'
SERVICE BULLETIN: VIB-2026-03
SUBJECT: Pre-Flight Vibration Baseline Configuration
VEHICLE: AC-SITL-001

To perform the baseline vibration analysis using Fast Fourier Transform (FFT), the flight controller's high-rate IMU batch logging must be configured. 

Please set the following ArduPilot parameters in QGroundControl (Vehicle Setup > Parameters):

1. INS_LOG_BAT_MASK = 1
   (Enables batch logging for the first IMU)

2. INS_LOG_BAT_OPT = 0
   (Captures both pre-filter and post-filter sensor data)

3. INS_HNTCH_ENABLE = 0
   (Disables the harmonic notch filter temporarily so we can record raw noise)

4. LOG_DISARMED = 1
   (Forces the flight controller to log data even while disarmed on the bench)

5. LOG_BITMASK = 65535
   (Enables Full Diagnostic Logging including fast attitude/IMU messages)

After setting all 5 parameters and ensuring they are saved to the vehicle, you MUST export the entire parameter configuration to a file for the engineering team.
Go to the QGC Parameters page, click 'Tools' (top right of the parameters screen), select 'Save to file', and save it exactly as:
/home/ga/Documents/QGC/vibration_prep.params
EOF
chown ga:ga /home/ga/Documents/QGC/vibration_test_bulletin.txt

# 3. Clean any existing output files
rm -f /home/ga/Documents/QGC/vibration_prep.params

# 4. Scramble the target parameters via pymavlink so a "do-nothing" agent gets 0 points
# These values are intentionally set opposite or different to the required target values
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
        
        # Scrambled defaults (differing from required)
        defaults = {
            b'INS_LOG_BAT_MASK': 0.0,
            b'INS_LOG_BAT_OPT': 1.0,
            b'INS_HNTCH_ENABLE': 1.0,
            b'LOG_DISARMED': 0.0,
            b'LOG_BITMASK': 895.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters successfully scrambled for baseline.")
    else:
        print("WARNING: Could not connect to SITL to scramble parameters.")
except Exception as e:
    print(f"WARNING: Parameter scramble script failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL and QGC are running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize the application
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== vibration_analysis_log_config task setup complete ==="
echo "Bulletin: /home/ga/Documents/QGC/vibration_test_bulletin.txt"
echo "Expected artifact: /home/ga/Documents/QGC/vibration_prep.params"