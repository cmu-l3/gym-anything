#!/bin/bash
echo "=== Setting up avionics_uart_peripheral_mapping task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the integration schematic document
cat > /home/ga/Documents/QGC/wiring_diagram.txt << 'WIRINGDOC'
CUSTOM AG-DRONE INTEGRATION SCHEMATIC
Vehicle: Hexa-Ag-Pro
Integrator: AG Systems Group
Date: 2026-03-09

=== HARDWARE TO SOFTWARE PORT MAPPING ===
Flight controllers label physical ports differently than software.
Use this map to find the correct ArduPilot software parameter namespace:

  Physical Port 'GPS 1'   --> Software: SERIAL3
  Physical Port 'GPS 2'   --> Software: SERIAL4
  Physical Port 'USER 1'  --> Software: SERIAL5
  Physical Port 'USER 2'  --> Software: SERIAL6

=== PERIPHERAL CONFIGURATION REQUIREMENTS ===
Configure both the PROTOCOL and BAUD parameters for each port in QGC.

1. Companion Computer (NVIDIA Jetson - AI Crop Scouting)
   - Connected to: GPS 1 (Software: SERIAL3)
   - Protocol: MAVLink 2 (Value: 2)
   - Baud Rate: 921600 (Value: 921)
   - Parameters to set: SERIAL3_PROTOCOL = 2, SERIAL3_BAUD = 921

2. Digital FPV System (DJI O3 Air Unit)
   - Connected to: GPS 2 (Software: SERIAL4)
   - Protocol: MSP (Value: 32)
   - Baud Rate: 115200 (Value: 115)
   - Parameters to set: SERIAL4_PROTOCOL = 32, SERIAL4_BAUD = 115

3. Agricultural Smart Pump ESC
   - Connected to: USER 1 (Software: SERIAL5)
   - Protocol: ESC Telemetry (Value: 16)
   - Baud Rate: 115200 (Value: 115)
   - Parameters to set: SERIAL5_PROTOCOL = 16, SERIAL5_BAUD = 115

4. Downward LIDAR (Lightware - Terrain Following)
   - Connected to: USER 2 (Software: SERIAL6)
   - Protocol: Rangefinder (Value: 9)
   - Baud Rate: 19200 (Value: 19)
   - Parameters to set: SERIAL6_PROTOCOL = 9, SERIAL6_BAUD = 19

=== INSTRUCTIONS ===
1. Open QGroundControl and navigate to Vehicle Setup (gears icon) > Parameters.
2. Search for the required parameters (e.g., "SERIAL3_PROT").
3. Set all 8 values exactly as specified above.
4. The system will prompt to reboot; you may ignore the reboot for this bench test.
WIRINGDOC

chown ga:ga /home/ga/Documents/QGC/wiring_diagram.txt

# 3. Reset target parameters to incorrect defaults so do-nothing = 0 pts
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
        
        # Reset to known defaults that explicitly differ from our targets
        defaults = {
            b'SERIAL3_PROTOCOL': 5.0,  # Default GPS
            b'SERIAL3_BAUD': 38.0,     # Default 38400
            b'SERIAL4_PROTOCOL': 5.0,  # Default GPS
            b'SERIAL4_BAUD': 38.0,     # Default 38400
            b'SERIAL5_PROTOCOL': -1.0, # Default None
            b'SERIAL5_BAUD': 57.0,     # Default 57600
            b'SERIAL6_PROTOCOL': -1.0, # Default None
            b'SERIAL6_BAUD': 57.0,     # Default 57600
        }
        
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Serial parameters reset to factory defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

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

echo "=== avionics_uart_peripheral_mapping task setup complete ==="
echo "Wiring Diagram: /home/ga/Documents/QGC/wiring_diagram.txt"