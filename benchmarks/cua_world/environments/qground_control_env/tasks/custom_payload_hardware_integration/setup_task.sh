#!/bin/bash
echo "=== Setting up custom_payload_hardware_integration task ==="

source /workspace/scripts/task_utils.sh

# 1. Create working directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the hardware wiring specification sheet
cat > /home/ga/Documents/QGC/hardware_wiring.txt << 'WIRINGDOC'
HARDWARE INTEGRATION WIRING SHEET
Drone: AC-SITL-007 (ArduCopter)
Payload: Multispectral Camera + 2-Axis Servo Gimbal

WIRING CONNECTIONS (Map to SERVOx_FUNCTION):
- Gimbal Pitch is connected to AUX 1 (SERVO9). Assign function: 7 (Mount1 Pitch)
- Gimbal Roll is connected to AUX 2 (SERVO10). Assign function: 8 (Mount1 Roll)
- Camera Trigger is connected to AUX 3 (SERVO11). Assign function: 10 (Camera Trigger)

SUBSYSTEM CONFIGURATION:
- Enable Mount 1 (MNT1_TYPE) as: 1 (Servo)
- Enable Camera 1 (CAM1_TYPE) as: 1 (Servo)

*** IMPORTANT: REBOOT REQUIRED ***
After enabling the Mount and Camera subsystems (changing MNT1_TYPE and CAM1_TYPE
from 0 to 1), you MUST reboot the flight controller. Use "Tools > Reboot Vehicle"
at the top of the Parameters view. Reconnect after the reboot to allow the
dynamic sub-parameters below to appear in the list.

DYNAMIC PARAMETERS (Configure after reboot):
- MNT1_PITCH_MIN : -60 (Prevents camera from hitting landing gear)
- MNT1_PITCH_MAX : 15  (Restricts upward tilt)
- CAM1_DURATION  : 5   (Shutter press duration)

When finished, create a log file at /home/ga/Documents/QGC/integration_log.txt
and write the following exact phrase inside it:
INTEGRATION COMPLETE: GIMBAL AND CAMERA
WIRINGDOC

chown ga:ga /home/ga/Documents/QGC/hardware_wiring.txt

# 3. Clean any existing log files to prevent gaming
rm -f /home/ga/Documents/QGC/integration_log.txt

# 4. Reset relevant ArduPilot parameters to default/0 to ensure active configuration
# This ensures that doing nothing results in a score of 0.
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
        # Reset parameters to 0 (disabled/unassigned)
        defaults = {
            b'MNT1_TYPE': 0.0,
            b'CAM1_TYPE': 0.0,
            b'SERVO9_FUNCTION': 0.0,
            b'SERVO10_FUNCTION': 0.0,
            b'SERVO11_FUNCTION': 0.0,
            b'MNT1_PITCH_MIN': -90.0,
            b'MNT1_PITCH_MAX': 90.0,
            b'CAM1_DURATION': 10.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.2)
        print("Hardware mapping parameters reset to defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL and QGC are running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize QGC window, clear dialogs
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== custom_payload_hardware_integration task setup complete ==="
echo "Wiring Sheet: /home/ga/Documents/QGC/hardware_wiring.txt"