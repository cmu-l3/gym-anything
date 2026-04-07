#!/bin/bash
echo "=== Setting up ppk_camera_hardware_integration task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the hardware integration schematic
cat > /home/ga/Documents/QGC/hardware_schematic.txt << 'SCHEMATIC'
HARDWARE INTEGRATION SCHEMATIC: SONY A7R IV PPK
Target: ArduCopter SITL Payload Upgrade
Date: 2026-03-10

WIRING MAPPING:
1. Camera Trigger Cable -> Pixhawk AUX 1 port
   (Software mapping: AUX 1 is controlled by the SERVO9_FUNCTION parameter)
   Action: Set SERVO9_FUNCTION to 10 (Camera Trigger)

2. Hotshoe Flash Feedback Cable -> Pixhawk AUX 5 port
   (Software mapping: AUX 5 digital pin is 54)
   Action: Set CAM_FEEDBACK_PIN to 54

CAMERA PARAMETERS:
- Trigger Method: Servo/PWM
  Action: Set CAM_TRIGG_TYPE to 1
  
- Shutter Hold Duration: 1.5 seconds
  Action: Set CAM_DURATION to 15 (value is in tenths of a second)
  
- Maximum Roll Limit: 25 degrees (prevents triggering in steep turns)
  Action: Set CAM_MAX_ROLL to 25
  
- Hotshoe Polarity: Active Low (Sony standard)
  Action: Set CAM_FEEDBACK_POL to 0

COMMISSIONING REPORT:
Create a text file at /home/ga/Documents/QGC/ppk_integration_report.txt
The report must confirm the installation and mention:
- The camera model ("Sony")
- The physical trigger port ("AUX 1")
- The physical feedback port ("AUX 5")
SCHEMATIC

chown ga:ga /home/ga/Documents/QGC/hardware_schematic.txt

# 3. Reset parameters to defaults (different from target values) to prevent gaming
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
        
        # Factory defaults that require changing
        defaults = {
            b'CAM_TRIGG_TYPE': 0.0,
            b'CAM_DURATION': 10.0,
            b'CAM_MAX_ROLL': 0.0,
            b'SERVO9_FUNCTION': 0.0,
            b'CAM_FEEDBACK_PIN': -1.0,
            b'CAM_FEEDBACK_POL': 1.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Integration parameters reset to factory defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing report
rm -f /home/ga/Documents/QGC/ppk_integration_report.txt

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

echo "=== ppk_camera_hardware_integration task setup complete ==="
echo "Schematic: /home/ga/Documents/QGC/hardware_schematic.txt"
echo "Expected Report: /home/ga/Documents/QGC/ppk_integration_report.txt"