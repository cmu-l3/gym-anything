#!/bin/bash
echo "=== Setting up rc_aux_failsafe_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write transmitter mapping document (agent must read this)
cat > /home/ga/Documents/QGC/transmitter_mapping.txt << 'MAPPINGDOC'
SPRAY DRONE TRANSMITTER MAPPING & FAILSAFE CONFIGURATION
Vehicle Type: Agricultural Octocopter
Controller: ArduCopter V4.5+
Date: 2026-03-10

=== AUXILIARY SWITCH CONFIGURATION ===
The custom 10-channel transmitter requires specific RC_OPTION assignments for channels 7 through 10.
Set the following parameters in QGroundControl (Vehicle Setup > Parameters):

- RC7_OPTION = 41
  (Function: Arm/Disarm. Required so the pilot can arm without the GCS.)

- RC8_OPTION = 31
  (Function: Motor Emergency Stop. Immediate motor kill for critical emergencies.)

- RC9_OPTION = 15
  (Function: Sprayer Enable. Toggles the main agricultural spray pump.)

- RC10_OPTION = 11
  (Function: Fence Enable/Disable. Enables the geofence mid-flight.)

=== THROTTLE FAILSAFE CONFIGURATION ===
If the RC link drops during a spray pass, the vehicle MUST land immediately to avoid spraying outside the field boundaries. Do NOT use the default RTL or Disable options.

- FS_THR_ENABLE = 2
  (Function: Land immediately on throttle failsafe.)

- FS_THR_VALUE = 925
  (Function: PWM threshold. The custom receiver outputs 900µs on link loss, so 925µs is the safe trigger threshold.)

=== PILOT INPUT FILTERING ===
To prevent altitude oscillations caused by stick jitter during precise spray passes:

- PILOT_THR_FILT = 4
  (Function: Filters throttle input at 4 Hz for smooth altitude control.)

Set all 7 parameters. The values are saved immediately to the flight controller over MAVLink.
MAPPINGDOC

chown ga:ga /home/ga/Documents/QGC/transmitter_mapping.txt

# 3. Reset all target parameters to factory defaults (which differ from required values)
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
        
        # Reset to known unsafe defaults
        defaults = {
            b'RC7_OPTION': 0.0,
            b'RC8_OPTION': 0.0,
            b'RC9_OPTION': 0.0,
            b'RC10_OPTION': 0.0,
            b'FS_THR_ENABLE': 0.0,
            b'FS_THR_VALUE': 975.0,
            b'PILOT_THR_FILT': 0.0,
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

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== rc_aux_failsafe_config task setup complete ==="
echo "Mapping Document: /home/ga/Documents/QGC/transmitter_mapping.txt"