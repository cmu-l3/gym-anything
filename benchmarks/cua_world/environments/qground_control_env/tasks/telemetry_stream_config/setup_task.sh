#!/bin/bash
echo "=== Setting up telemetry_stream_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write bandwidth planning document
cat > /home/ga/Documents/QGC/bandwidth_plan.txt << 'PLANDOC'
LONG-RANGE TELEMETRY BANDWIDTH PLAN
Mission: Wetland Corridor Wildlife Survey (12 km)
Link: 900 MHz SiK Radio (19.2 kbps capacity)
Date: 2026-03-10

ISSUE:
The factory default MAVLink stream rates saturate our low-bandwidth radio link,
causing severe latency in map updates and occasional link loss.

SOLUTION:
Optimize the MAVLink stream rates for Serial 0 (SR0) which connects to the
ground station. We must reduce non-essential data while increasing the position
update rate for smooth tracking on the map.

REQUIRED PARAMETER CONFIGURATION (QGC > Vehicle Setup > Parameters):

Stream Parameter | Target Rate | Description / Reason
-----------------|-------------|-------------------------------------------
SR0_RAW_SENS     | 1 Hz        | Raw sensors (IMU/Baro/Mag) - reduce from 2
SR0_EXT_STAT     | 1 Hz        | Extended status (GPS/Bat) - reduce from 2
SR0_RC_CHAN      | 0 Hz        | RC channels - disable, not needed for auto
SR0_RAW_CTRL     | 0 Hz        | Servo outputs - disable, not needed for auto
SR0_POSITION     | 3 Hz        | GPS position - INCREASE from 2 to track smoothly
SR0_EXTRA1       | 4 Hz        | Attitude (roll/pitch) - reduce from 10
SR0_EXTRA2       | 1 Hz        | VFR HUD (airspeed/alt) - reduce from 4
SR0_EXTRA3       | 1 Hz        | AHRS/HW status - reduce from 2

ACTION REQUIRED:
1. Search for each SR0_* parameter in QGroundControl.
2. Set them to the Target Rate listed above.
3. Once all 8 are configured, write a brief summary report to:
   /home/ga/Documents/QGC/bandwidth_report.txt

The report must list the 8 parameter names, their new rates, and what they control.
PLANDOC

chown ga:ga /home/ga/Documents/QGC/bandwidth_plan.txt

# 3. Reset all target parameters to factory defaults (saturating state)
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
        # Reset to defaults that differ from our required values
        defaults = {
            b'SR0_RAW_SENS': 2.0,
            b'SR0_EXT_STAT': 2.0,
            b'SR0_RC_CHAN':  2.0,
            b'SR0_RAW_CTRL': 1.0,
            b'SR0_POSITION': 2.0,
            b'SR0_EXTRA1':   10.0,
            b'SR0_EXTRA2':   4.0,
            b'SR0_EXTRA3':   2.0,
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

# 4. Remove any pre-existing report
rm -f /home/ga/Documents/QGC/bandwidth_report.txt

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

echo "=== telemetry_stream_config task setup complete ==="
echo "Plan document: /home/ga/Documents/QGC/bandwidth_plan.txt"