#!/bin/bash
echo "=== Setting up volcanic_crater_thermal_overwatch task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directory structure
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the geological operations brief
cat > /home/ga/Documents/QGC/volcano_brief.txt << 'BRIEFDOC'
VOLCANIC CRATER THERMAL OVERWATCH - MISSION BRIEF
Target: Mt. SITL Active Vent
Date: 2026-03-10
Prepared by: Geosciences Lead

=== PAYLOAD CONFIGURATION ===
The drone is equipped with a thermal camera streaming via an onboard companion computer.
You must configure QGroundControl to display this stream.
1. Click the QGC Icon (top-left) > Application Settings > General.
2. Scroll down to the Video section.
3. Set Video Source to: "RTSP Video Stream"
4. Set RTSP URL to: rtsp://192.168.144.25:8554/thermal

=== SAFETY PARAMETERS ===
The crater rim is 150 meters high. The default Return-to-Launch altitude (15m) will cause a collision with the crater wall if signal is lost.
1. Go to Vehicle Setup (Gear/Wrench Icon) > Parameters.
2. Find the RTL_ALT parameter.
3. Set it to 15000 (which is 150 meters).
4. Save the parameter.

=== FLIGHT PLAN ===
Create a new mission in Plan View. The drone must fly to a safe standoff distance, point the camera at the vent, and hold position for 30 minutes to capture continuous thermal data.

Required Mission Sequence:
1. Takeoff (Altitude: 150m)
2. Waypoint at Standoff Position: 47.3990 N, 8.5475 E (Altitude: 150m)
3. Region of Interest (ROI) targeting the Vent: 47.3980 N, 8.5460 E (Altitude: 50m)
   *This forces the camera to point down at the vent for the remainder of the flight.*
4. Loiter (Time) at the Standoff Position for 1800 seconds (30 minutes).
5. Return to Launch (RTL).

Save the completed mission to:
/home/ga/Documents/QGC/crater_monitor.plan
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/volcano_brief.txt

# 3. Purge any existing RTSP URL from the QGC config to ensure a clean slate
sed -i '/rtspUrl=/d' /home/ga/.config/QGroundControl/QGroundControl.ini 2>/dev/null || true

# 4. Reset RTL_ALT to the dangerous default (1500) so do-nothing = 0 pts
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
        # Reset to known default that differs from required value
        master.mav.param_set_send(sysid, compid, b'RTL_ALT', 1500.0, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
        time.sleep(0.3)
        print("RTL_ALT reset to default (1500)")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time

# 6. Ensure Environment is Running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus, Maximize, and Dismiss startup popups
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== volcanic_crater_thermal_overwatch setup complete ==="