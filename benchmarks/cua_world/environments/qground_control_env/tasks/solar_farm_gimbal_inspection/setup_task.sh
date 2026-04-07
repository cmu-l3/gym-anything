#!/bin/bash
echo "=== Setting up solar_farm_gimbal_inspection task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write inspection brief
cat > /home/ga/Documents/QGC/inspection_brief.txt << 'BRIEFDOC'
SOLAR FARM INSPECTION BRIEF
Site: Zurich South Solar Array
Date: 2026-03-10
Inspector: Operations Team

=== TARGET SUBSTATIONS ===
The drone must visit the following 3 transformer substations.

1. Substation Alpha
   Latitude: 47.3980
   Longitude: 8.5450

2. Substation Beta
   Latitude: 47.3990
   Longitude: 8.5460

3. Substation Gamma
   Latitude: 47.3985
   Longitude: 8.5470

=== MISSION PROFILE FOR EACH TARGET ===
You must configure a "stop-and-stare" sequence for every target:
- Navigate to target (Waypoint altitude: 30 m)
- Point camera down (Mount Control, Pitch: -60 deg)
- Stabilize sensor (Loiter Time: 15 seconds)
- Reset camera for forward flight (Mount Control, Pitch: 0 deg)

Note: Do not forget to add a Takeoff command at the start, and an RTL 
command at the very end of the mission.

=== REQUIRED HARDWARE CONFIGURATION ===
The drone's gimbal is currently disabled. 
In Vehicle Parameters, you must set MNT1_TYPE to 2 (MAVLink) before flight.

Save the completed mission plan to: /home/ga/Documents/QGC/solar_patrol.plan
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/inspection_brief.txt
rm -f /home/ga/Documents/QGC/solar_patrol.plan

# 3. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset MNT1_TYPE parameter to 0 (default) via pymavlink
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # Let MAVLink channel stabilize
        
        # Reset MNT1_TYPE to 0 (None)
        master.mav.param_set_send(sysid, compid, b'MNT1_TYPE', 0.0, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
        time.sleep(0.5)
        print("MNT1_TYPE reset to 0 (None)")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

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

echo "=== solar_farm_gimbal_inspection task setup complete ==="
echo "Brief: /home/ga/Documents/QGC/inspection_brief.txt"
echo "Expected plan: /home/ga/Documents/QGC/solar_patrol.plan"