#!/bin/bash
echo "=== Setting up water_quality_sampling_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the protocol document
cat > /home/ga/Documents/QGC/sampling_protocol.txt << 'PROTODOC'
ENVIRONMENTAL WATER QUALITY SAMPLING PROTOCOL
Mission: Toxic Algal Bloom Sampling
Target Body: Lake Greifensee, Sector C
Date: 2026-03-09

=== SAFETY & DESCENT PARAMETERS ===
Because the drone will fly very close to the water surface, we must
adjust the flight controller parameters to ensure a safe descent and return.
Set the following parameters in QGC (Vehicle Setup > Parameters):

1. RTL_ALT: 2000
   (2000 cm = 20 meters. This ensures the drone climbs to 20m before returning).

2. WPNAV_SPEED_DN: 50
   (50 cm/s = 0.5 m/s. This slows the automatic descent to prevent plunging into the water).

=== FLIGHT PLAN REQUIREMENTS ===
Create a new mission plan to perform the automated sampling:

1. Target Location: Lat 47.3970, Lon 8.5450
2. Transit: Fly to the target location at 20m altitude.
3. Descent: Descend to 2m altitude at the target location.
4. Activate Pump: Add a "Set relay" command (Relay 1, Value: On) to start the water pump.
5. Sampling Time: Add a "Loiter (Time)" command for 45 seconds to collect the sample.
6. Deactivate Pump: Add a "Set relay" command (Relay 1, Value: Off) to stop the pump.
7. Return: Add a "Return to Launch" (RTL) command to finish the mission.

Save the completed mission plan to:
/home/ga/Documents/QGC/water_sampling.plan
PROTODOC

chown ga:ga /home/ga/Documents/QGC/sampling_protocol.txt

# 3. Reset parameters to defaults so do-nothing = 0 pts
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
        # Reset parameters to known defaults
        defaults = {
            b'RTL_ALT': 1500.0,
            b'WPNAV_SPEED_DN': 150.0,
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

# 4. Remove any existing mission plan
rm -f /home/ga/Documents/QGC/water_sampling.plan

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

echo "=== water_quality_sampling_mission task setup complete ==="
echo "Protocol: /home/ga/Documents/QGC/sampling_protocol.txt"