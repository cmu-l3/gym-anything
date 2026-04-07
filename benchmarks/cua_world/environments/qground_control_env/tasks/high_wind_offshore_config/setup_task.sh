#!/bin/bash
echo "=== Setting up high_wind_offshore_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the operational briefing document
cat > /home/ga/Documents/QGC/offshore_briefing.txt << 'BRIEFDOC'
═══════════════════════════════════════════════════════
  SKJÁLFANDI BAY OFFSHORE UAV DEPLOYMENT BRIEFING
  Project: Cetacean Tagging & Observation
  Date: 2026-03-10
═══════════════════════════════════════════════════════

ENVIRONMENTAL HAZARDS:
  - Sustained headwinds: 12 m/s (23 knots)
  - Gusts: Up to 18 m/s
  - Boundary layer: Wind speed increases significantly above 10m AGL.

MANDATORY AIRFRAME TUNING:
  To prevent the vehicle from being blown out to sea, the flight 
  envelope limits must be expanded from factory defaults.

  1. Max Lean Angle: 45 degrees 
     (Allows the drone to pitch aggressively into the wind)
  2. Waypoint Navigation Speed: 12 m/s
  3. Waypoint Acceleration: 2.5 m/s²
     (Needed for rapid gust response)
  4. Return-to-Launch (RTL) Speed: 15 m/s
     (Critical: RTL speed must exceed the headwind for safe return)
  5. Return-to-Launch Altitude: 5 m
     (Keep the drone low during return to avoid higher winds aloft)
  6. EKF Failsafe Threshold: 1.0
     (Relax the Extended Kalman Filter threshold to tolerate 
      turbulent buffeting over the waves)

POST-TUNING CERTIFICATION:
  After applying the above parameters, the technician must verify 
  the vehicle's System ID (SYSID_THISMAV).
  Create a sign-off document at: /home/ga/Documents/QGC/wind_certification.txt
  
  The document must contain:
  - "Max Angle: 45 degrees"
  - "RTL Speed: 15 m/s"
  - "Vehicle System ID: [value]"
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/offshore_briefing.txt

# 3. Clean any existing report files from previous runs
rm -f /home/ga/Documents/QGC/wind_certification.txt

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Reset target parameters to default values to ensure 'do-nothing' fails
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
        
        # Defaults explicitly different from the required offshore targets
        defaults = {
            b'ANGLE_MAX': 3000.0,
            b'WPNAV_SPEED': 500.0,
            b'WPNAV_ACCEL': 100.0,
            b'RTL_SPEED': 0.0,
            b'RTL_ALT': 1500.0,
            b'FS_EKF_THRESH': 0.8
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 7. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== high_wind_offshore_config task setup complete ==="
echo "Briefing: /home/ga/Documents/QGC/offshore_briefing.txt"