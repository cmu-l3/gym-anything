#!/bin/bash
echo "=== Setting up ag_sprayer_system_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the integration manual
cat > /home/ga/Documents/QGC/sprayer_integration_manual.txt << 'MANDOC'
AGRICULTURAL SPRAYER INTEGRATION MANUAL
Module: Liquid Application System v2.1
Aircraft: ArduCopter Heavy-Lift Hex
Date: 2026-03-10

=== SYSTEM OVERVIEW ===
This aircraft is equipped with an automated liquid spray system. The ArduPilot
flight controller must be configured to assume control of the pump and rotary
spinners to ensure precise application and prevent chemical pooling when the
aircraft decelerates at field boundaries.

=== REQUIRED PARAMETER CONFIGURATION ===
You must configure the following 6 parameters using QGroundControl.
(Navigate to the Q icon -> Vehicle Setup -> Parameters -> Search)

1. SYSTEM ACTIVATION
   Parameter: SPRAY_ENABLE
   Required Value: 1
   (Enables the internal sprayer logic module. Default is 0.)

2. OUTPUT PORT MAPPING
   The main pump ESC is plugged into AUX 1. The spinner ESC is on AUX 2.
   Map these in the servo configuration:
   Parameter: SERVO9_FUNCTION
   Required Value: 22 (Sprayer Pump)
   
   Parameter: SERVO10_FUNCTION
   Required Value: 23 (Sprayer Spinner)

3. SAFETY & FLOW RATE LIMITS
   To prevent toxic chemical pooling, the pump must shut off if the drone
   slows down below 2.5 m/s. (250 cm/s).
   Parameter: SPRAY_SPEED_MIN
   Required Value: 250

   The pump stalls if driven below 15% capacity. Set the minimum pump floor.
   Parameter: SPRAY_PUMP_MIN
   Required Value: 15

   Set the nominal baseline chemical flow rate to 80% for this payload.
   Parameter: SPRAY_PUMP_RATE
   Required Value: 80

=== INSTRUCTIONS ===
Use the QGroundControl Parameters menu to find and set all 6 values exactly as
specified above. Values are written to the flight controller immediately upon
clicking 'Save' or hitting Enter.
MANDOC

chown ga:ga /home/ga/Documents/QGC/sprayer_integration_manual.txt

# 3. Reset parameters to defaults (prevent false positives if run multiple times)
# Factory defaults differ from all required values
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
        
        # Reset to known factory defaults that differ from the target values
        defaults = {
            b'SPRAY_ENABLE': 0.0,
            b'SERVO9_FUNCTION': 0.0,
            b'SERVO10_FUNCTION': 0.0,
            b'SPRAY_SPEED_MIN': 100.0,
            b'SPRAY_PUMP_MIN': 0.0,
            b'SPRAY_PUMP_RATE': 10.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Spray parameters successfully reset to factory defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# 5. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

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

echo "=== ag_sprayer_system_config task setup complete ==="
echo "Integration manual: /home/ga/Documents/QGC/sprayer_integration_manual.txt"