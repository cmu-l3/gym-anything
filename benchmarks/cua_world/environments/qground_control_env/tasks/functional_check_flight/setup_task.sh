#!/bin/bash
echo "=== Setting up functional_check_flight task ==="

source /workspace/scripts/task_utils.sh

# 1. Create working directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write Standard Operating Procedure (SOP)
cat > /home/ga/Documents/QGC/preflight_procedure.txt << 'SOPDOC'
STANDARD OPERATING PROCEDURE: FUNCTIONAL CHECK FLIGHT
Vehicle: ArduCopter AC-SITL-007
Task: Pre-deployment Live Hover & RTL Test

WARNING: Do not deploy vehicle to customer sites without completing this test.

=== PROCEDURE ===
1. Verify QGroundControl is connected and vehicle shows "Ready To Fly" (GPS lock achieved).
2. ARM the vehicle using the QGC action slider.
3. Command a TAKEOFF to exactly 25 meters altitude.
4. Allow the vehicle to reach 25m.
5. Observe the telemetry (HUD) for 15-20 seconds to confirm stable position hold.
   Note the GPS coordinates and the exact altitude achieved.
6. Command RTL (Return to Launch) via the Flight Mode menu or Action slider.
7. Observe the vehicle returning, descending, and landing.
8. Wait for the vehicle to automatically DISARM after landing.

=== POST-FLIGHT REPORT ===
Once the flight is complete, create a plain text report at:
/home/ga/Documents/QGC/check_flight_report.txt

Your report must include:
- Maximum observed altitude (e.g., "Altitude: 25.1 m")
- Hover GPS coordinates (Latitude and Longitude)
- A brief statement on whether RTL completed successfully
- Final Status: Must include the word "PASS" if the vehicle flew and landed safely.

Example Format:
Flight Test Report
Max Altitude: 25.0 m
GPS Position: Lat -35.363, Lon 149.165
RTL Behavior: Successful return and auto-land.
Status: PASS
SOPDOC

chown ga:ga /home/ga/Documents/QGC/preflight_procedure.txt

# 3. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Wait for SITL EKF/GPS to be fully aligned (Required for arming)
echo "--- Waiting for EKF/Pre-Arm Checks ---"
python3 << 'PYEOF'
import time
from pymavlink import mavutil

try:
    master = mavutil.mavlink_connection('tcp:localhost:5762')
    master.wait_heartbeat(timeout=10)
    print("Heartbeat received. Waiting for EKF alignment (up to 45s)...")
    start = time.time()
    while time.time() - start < 45:
        # Check SYS_STATUS for MAV_SYS_STATUS_PREARM_CHECK flag (bit 23 -> 0x400000)
        msg = master.recv_match(type='SYS_STATUS', blocking=True, timeout=1)
        if msg:
            if (msg.onboard_control_sensors_health & 0x400000) == 0x400000:
                print("EKF and Pre-arm checks passed! Vehicle is Ready to Fly.")
                break
except Exception as e:
    print(f"Warning during EKF check: {e}")
PYEOF

# 5. Record initial flight statistics to ensure we measure delta
echo "--- Recording initial parameters ---"
python3 << 'PYEOF' > /tmp/initial_stats.json
import json, time
from pymavlink import mavutil
result = {'STAT_FLTTIME': 0, 'STAT_RUNTIME': 0}
try:
    master = mavutil.mavlink_connection('tcp:localhost:5762')
    master.wait_heartbeat(timeout=5)
    for param in [b'STAT_FLTTIME', b'STAT_RUNTIME']:
        master.mav.param_request_read_send(master.target_system, master.target_component, param, -1)
        pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=2)
        if pmsg:
            result[param.decode('utf-8')] = pmsg.param_value
except:
    pass
print(json.dumps(result))
PYEOF

# 6. Record task start time
date +%s > /tmp/task_start_time

# 7. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== functional_check_flight task setup complete ==="
echo "SOP Document: /home/ga/Documents/QGC/preflight_procedure.txt"