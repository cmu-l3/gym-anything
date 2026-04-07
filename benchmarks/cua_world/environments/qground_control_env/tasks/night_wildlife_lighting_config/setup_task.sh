#!/bin/bash
echo "=== Setting up night_wildlife_lighting_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the operations brief
cat > /home/ga/Documents/QGC/night_ops_brief.txt << 'OPDOC'
NIGHT OPERATIONS BRIEF - WOLF PACK TRACKING
Date: 2026-03-10
Location: Yellowstone National Park (Sector 4)
Payload: Thermal Imager + 100W LED Spotlight

LIGHTING CONFIGURATION:
- The LED spotlight is connected to the Pixhawk flight controller on AUX 5.
- You must configure Relay 1 to use this pin (Pin 54).
- The pilot will control the spotlight using Switch E on the radio, which transmits on RC Channel 9.
- Assign RC Channel 9 to toggle Relay 1.

NIGHT FLIGHT SAFETY PARAMETERS:
(Note: Pay close attention to the required units in the QGC parameter editor! You may need to convert values.)
- To ensure safety in low visibility, reduce the maximum automated waypoint flight speed to 3 m/s.
- To prevent sudden movements that might startle the wildlife, reduce the waypoint acceleration to 1 m/s/s.
- The survey area has tall pine trees reaching 40 meters. Set the Return-To-Launch (RTL) altitude to 50 meters to ensure obstacle clearance in the dark.

INSTRUCTIONS:
Open QGroundControl, navigate to Vehicle Setup (the "Q" menu -> Vehicle Setup), select Parameters, and search for the necessary parameters to update them.
OPDOC

chown ga:ga /home/ga/Documents/QGC/night_ops_brief.txt

# 3. Reset target parameters to defaults so do-nothing = 0 pts
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
        # Factory defaults (differ from the required night config)
        defaults = {
            b'RELAY_PIN': 13.0,
            b'RC9_OPTION': 0.0,
            b'WPNAV_SPEED': 500.0,
            b'WPNAV_ACCEL': 250.0,
            b'RTL_ALT': 1500.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory defaults")
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

echo "=== night_wildlife_lighting_config task setup complete ==="
echo "Brief: /home/ga/Documents/QGC/night_ops_brief.txt"