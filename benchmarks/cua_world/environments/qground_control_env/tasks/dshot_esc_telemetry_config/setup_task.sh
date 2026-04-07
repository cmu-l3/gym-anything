#!/bin/bash
echo "=== Setting up dshot_esc_telemetry_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the hardware build sheet
cat > /home/ga/Documents/QGC/esc_build_sheet.txt << 'BUILDDOC'
HARDWARE BUILD SHEET & COMMISSIONING INSTRUCTIONS
Vehicle: Heavy-Lift X8 (AC-SITL-DSHOT)
Technician: Assembly Team
Date: 2026-03-09

=== WIRING SUMMARY ===
- Main Motors: Connected to standard PWM outputs 1-8
- ESC Type: 80A BLHeli32 Digital ESCs
- ESC Telemetry Wire: Soldered to TELEM 2 (Serial 2) RX pin
- Motors: 28-pole high-torque pancake motors

=== REQUIRED PARAMETER CHANGES ===
The flight controller is currently at factory defaults (Analog PWM, no telemetry).
You must use QGroundControl (Vehicle Setup > Parameters) to configure the following 7 parameters:

1. MOTOR OUTPUT PROTOCOL
   Parameter: MOT_PWM_TYPE
   Required Value: 6 (DShot600)

2. ESC TELEMETRY PORT MAPPING
   Parameter: SERIAL2_PROTOCOL
   Required Value: 16 (ESC Telemetry)
   
   Parameter: SERIAL2_BAUD
   Required Value: 115 (115200 bps)

3. BLHELI CONFIGURATION
   Parameter: SERVO_BLH_AUTO
   Required Value: 1 (Enable BLHeli auto-telemetry)
   
   Parameter: SERVO_BLH_POLES
   Required Value: 28 (Matches our 28-pole motors)

4. HARMONIC NOTCH FILTER (RPM-BASED)
   Parameter: INS_HNTCH_ENABLE
   Required Value: 1 (Enable the filter)

   *** CRITICAL WORKFLOW NOTE ***
   Harmonic notch settings are dynamically generated. After setting INS_HNTCH_ENABLE = 1, 
   you MUST reboot the vehicle (click the "Reboot Vehicle" warning at the top of QGC).
   Wait for the vehicle to reconnect. ONLY THEN will the next parameter appear.

   Parameter: INS_HNTCH_MODE
   Required Value: 3 (ESC Telemetry mode)

Ensure all 7 parameters are saved to the vehicle before concluding the task.
BUILDDOC

chown ga:ga /home/ga/Documents/QGC/esc_build_sheet.txt

# 3. Reset all target parameters to defaults so do-nothing = 0 pts
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
        
        # Reset to known factory defaults that differ from required values
        defaults = {
            b'MOT_PWM_TYPE': 0.0,       # Normal PWM
            b'SERIAL2_PROTOCOL': 2.0,   # MAVLink 2
            b'SERIAL2_BAUD': 57.0,      # 57600
            b'SERVO_BLH_AUTO': 0.0,     # Disabled
            b'SERVO_BLH_POLES': 14.0,   # Standard 14 pole
            b'INS_HNTCH_ENABLE': 0.0,   # Disabled
            b'INS_HNTCH_MODE': 0.0,     # Default
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

echo "=== dshot_esc_telemetry_config task setup complete ==="
echo "Build sheet: /home/ga/Documents/QGC/esc_build_sheet.txt"