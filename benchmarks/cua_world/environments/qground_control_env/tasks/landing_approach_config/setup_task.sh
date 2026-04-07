#!/bin/bash
echo "=== Setting up landing_approach_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write operations brief
cat > /home/ga/Documents/QGC/landing_ops_brief.txt << 'OPDOC'
=== LANDING APPROACH OPERATIONS BRIEF ===
Site: Greenfield South Paddock, NSW Australia
Date: 2026-03-10
Operator: AgriDrone Solutions Pty Ltd

HAZARD ASSESSMENT:
- North boundary: 15m eucalyptus windbreak (OBSTACLE)
- South boundary: Clear approach from gravel road
- Approach corridor: FROM SOUTH (mandatory)

BASE STATION COORDINATES:
  Latitude:  47.3977
  Longitude: 8.5456
  (Note: SITL home coordinates used for simulation)

MISSION PROFILE:
1. Takeoff to 50m AGL
2. Fly to survey start point: lat 47.3985, lon 8.5460, alt 50m
3. Begin landing approach sequence (insert DO_LAND_START marker)
4. Approach waypoint 1: lat 47.3970, lon 8.5456, alt 35m
5. Approach waypoint 2: lat 47.3973, lon 8.5456, alt 18m
6. Approach waypoint 3: lat 47.3975, lon 8.5456, alt 8m
7. Land at base station coordinates (insert LAND command)

LANDING PARAMETERS (mandatory for heavy spray payload):
  LAND_SPEED     = 50    (cm/s — final descent 0.5 m/s)
  LAND_ALT_LOW   = 1000  (cm — begin slow descent at 10m AGL)
  WPNAV_SPEED_DN = 100   (cm/s — waypoint descent rate 1.0 m/s)

NOTE: Default LAND_SPEED and LAND_ALT_LOW may already be correct on some
      firmware versions, but WPNAV_SPEED_DN usually defaults to 150.
      Verify ALL three parameters are set exactly as above before flight.
      
      Save the mission plan to: /home/ga/Documents/QGC/approach_landing.plan
===
OPDOC

chown ga:ga /home/ga/Documents/QGC/landing_ops_brief.txt

# 3. Reset landing parameters to known states (ensure WPNAV_SPEED_DN is wrong)
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
        # Set parameters. Note that LAND_SPEED and LAND_ALT_LOW match defaults (and the required values)
        # but WPNAV_SPEED_DN is set to 150, which MUST be changed to 100 by the agent.
        defaults = {
            b'LAND_SPEED': 50.0,
            b'LAND_ALT_LOW': 1000.0,
            b'WPNAV_SPEED_DN': 150.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Landing parameters reset to defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing plan
rm -f /home/ga/Documents/QGC/approach_landing.plan

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL and QGC are running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus, maximize, and take screenshot
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

take_screenshot /tmp/task_start_screenshot.png

echo "=== landing_approach_config task setup complete ==="