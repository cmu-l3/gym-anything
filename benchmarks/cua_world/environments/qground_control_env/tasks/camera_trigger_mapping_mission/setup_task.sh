#!/bin/bash
echo "=== Setting up camera_trigger_mapping_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Clean up any previous plans
rm -f /home/ga/Documents/QGC/mapping_camera_mission.plan

# 3. Write operations brief
cat > /home/ga/Documents/QGC/mapping_ops_brief.txt << 'OPDOC'
AERIAL MAPPING OPERATIONS BRIEF
================================
Project: Agricultural Field Orthomosaic — Paddock 7
Client: AgroDrone Analytics Pty Ltd
Date: 2026-03-09

FLIGHT PARAMETERS
-----------------
Navigation Speed: 8 m/s (set WPNAV_SPEED = 800)
Mission Altitude: 120 m AGL (all waypoints)
Minimum Waypoints: 4 navigation waypoints covering the strip

CAMERA CONFIGURATION
--------------------
Trigger Method: Distance-based (DO_SET_CAM_TRIGG_DIST, MAV command 206)
Trigger Interval: 25 meters
Activation: Insert trigger-start command (distance=25) AFTER the first
            navigation waypoint (to begin capturing over the target area)
Deactivation: Insert trigger-stop command (distance=0) BEFORE the final
              navigation waypoint (to stop capturing before return transit)

MISSION STRUCTURE
-----------------
1. Takeoff
2. Navigate to first waypoint (transit — no photos)
3. Activate camera trigger (DO_SET_CAM_TRIGG_DIST, distance=25)
4. Navigate mapping strip waypoints at 120m altitude
5. Deactivate camera trigger (DO_SET_CAM_TRIGG_DIST, distance=0)
6. Navigate to final waypoint
7. RTL (Return to Launch)

SAVE LOCATION
-------------
Save the completed plan to:
  /home/ga/Documents/QGC/mapping_camera_mission.plan

NOTES
-----
- Use the QGC Plan View to build the mission
- Camera trigger commands are DO-type items inserted between waypoints
- The vehicle parameter WPNAV_SPEED must be set to 800 via Vehicle Setup > Parameters
- Place waypoints near the vehicle's current location
OPDOC

chown ga:ga /home/ga/Documents/QGC/mapping_ops_brief.txt

# 4. Reset WPNAV_SPEED to default (500) so do-nothing fails
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
        master.mav.param_set_send(sysid, compid, b'WPNAV_SPEED', 500.0,
                                  mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
        time.sleep(0.5)
        print("WPNAV_SPEED reset to default (500.0)")
    else:
        print("WARNING: Could not connect to SITL to reset WPNAV_SPEED")
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

# 7. Focus, maximize, and dismiss startup dialogs
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== camera_trigger_mapping_mission task setup complete ==="
echo "Operations brief: /home/ga/Documents/QGC/mapping_ops_brief.txt"
echo "Expected output: /home/ga/Documents/QGC/mapping_camera_mission.plan"