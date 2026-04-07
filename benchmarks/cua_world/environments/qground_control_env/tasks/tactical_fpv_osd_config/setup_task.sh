#!/bin/bash
echo "=== Setting up tactical_fpv_osd_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the SOP document that the agent must read
cat > /home/ga/Documents/QGC/tactical_osd_sop.txt << 'SOPDOC'
TACTICAL FPV DRONE - OSD CONFIGURATION SOP
Department: Special Operations / Technical Unit
Vehicle Profile: Indoor Breaching FPV
Date: 2026-03-10

=== OSD REQUIREMENT ===
Our analog FPV feeds must remain completely clear in the center grid for target identification. 
All telemetry MUST be pushed to the corners. 
ArduPilot OSD grid dimensions are 30 (X) by 16 (Y).

=== SYSTEM ENABLE ===
OSD_TYPE = 1 (MAX7456)
OSD1_ENABLE = 1

=== REQUIRED TELEMETRY ELEMENTS (Corners) ===
Enable these items and set their exact X and Y coordinates:

1. Flight Mode (OSD1_FLTMODE)
   Enable: 1
   X: 2
   Y: 1
   
2. Battery Voltage (OSD1_BAT_VOLT)
   Enable: 1
   X: 2
   Y: 14
   
3. Current Draw (OSD1_CURRENT)
   Enable: 1
   X: 22
   Y: 14
   
4. RSSI / Signal Strength (OSD1_RSSI)
   Enable: 1
   X: 22
   Y: 1

=== CLUTTER REMOVAL ===
Disable these default elements to clear the center view:
- Altitude (OSD1_ALTITUDE_EN = 0)
- System Messages (OSD1_MESSAGE_EN = 0)

Configure these parameters in QGroundControl (Vehicle Setup > Parameters).
SOPDOC

chown ga:ga /home/ga/Documents/QGC/tactical_osd_sop.txt

# 3. Reset all target parameters to incorrect defaults so "do nothing" fails
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
        # Note: OSD_TYPE is kept at 1 so OSD1 parameters don't get hidden by ArduPilot,
        # but OSD1_ENABLE is 0 to ensure screen is off by default.
        defaults = {
            b'OSD_TYPE': 1.0,         
            b'OSD1_ENABLE': 0.0,      
            b'OSD1_FLTMODE_EN': 0.0, b'OSD1_FLTMODE_X': 10.0, b'OSD1_FLTMODE_Y': 5.0,
            b'OSD1_BAT_VOLT_EN': 0.0, b'OSD1_BAT_VOLT_X': 15.0, b'OSD1_BAT_VOLT_Y': 5.0,
            b'OSD1_CURRENT_EN': 0.0, b'OSD1_CURRENT_X': 10.0, b'OSD1_CURRENT_Y': 10.0,
            b'OSD1_RSSI_EN': 0.0, b'OSD1_RSSI_X': 15.0, b'OSD1_RSSI_Y': 10.0,
            b'OSD1_ALTITUDE_EN': 1.0, 
            b'OSD1_MESSAGE_EN': 1.0,  
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.1)
        print("OSD parameters reset to incorrect defaults")
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

echo "=== tactical_fpv_osd_config task setup complete ==="
echo "SOP Document: /home/ga/Documents/QGC/tactical_osd_sop.txt"