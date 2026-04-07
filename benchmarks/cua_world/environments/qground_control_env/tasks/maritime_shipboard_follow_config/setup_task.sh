#!/bin/bash
echo "=== Setting up maritime_shipboard_follow_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write deployment brief
cat > /home/ga/Documents/QGC/maritime_brief.txt << 'BRIEF'
MARITIME DEPLOYMENT BRIEF
Operation: Search and Rescue Sector 4
Vessel: USCGC Sentinel
Date: 2026-03-10

=== VESSEL SPECIFICATIONS ===
Vessel Length: 120 meters
MAVLink Beacon System ID: 112

=== FOLLOW MODE REQUIREMENTS ===
To safely follow the vessel, you must set the following parameters:
1. FOLL_ENABLE = 1 (Enable Follow Mode)
2. FOLL_SYSID = 112 (Target the ship's beacon ID)
3. FOLL_OFS_X = [Calculate this!] (Set to exactly half the ship's length BEHIND the vessel. Remember: forward is positive, backward is negative)
4. FOLL_OFS_Z = 45 (Maintain 45m altitude above the vessel)
5. FOLL_YAW_BEHAV = 2 (Face the lead vehicle's heading)

=== PILOT & SAFETY OVERRIDES ===
6. FLTMODE6 = 17 (Set flight mode 6 to 'Follow' for the pilot's emergency switch)
7. FS_GCS_ENABLE = 0 (Disable GCS failsafe to prevent an ocean RTL if ground station connection drops)

=== EMERGENCY COASTAL DIVERT (RALLY POINT) ===
If a catastrophic failure occurs near the coastline, the drone must have a land-based emergency divert point.
Create a Rally Point with these exact coordinates:
  Latitude: -35.3655
  Longitude: 149.1610
  Altitude: 15 m

Save the Rally Point plan to:
/home/ga/Documents/QGC/coastal_divert.plan
BRIEF

chown ga:ga /home/ga/Documents/QGC/maritime_brief.txt

# 3. Reset parameters to factory defaults (0 or 1 for failsafes)
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
        defaults = {
            b'FOLL_ENABLE': 0.0,
            b'FOLL_SYSID': 0.0,
            b'FOLL_OFS_X': 0.0,
            b'FOLL_OFS_Z': 0.0,
            b'FOLL_YAW_BEHAV': 0.0,
            b'FLTMODE6': 0.0,
            b'FS_GCS_ENABLE': 1.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.2)
        print("Parameters reset")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any existing Rally Point plans
rm -f /home/ga/Documents/QGC/coastal_divert.plan

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure applications are running
ensure_sitl_running
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="