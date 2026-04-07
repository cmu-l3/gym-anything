#!/bin/bash
echo "=== Setting up emergency_medical_cargo_drop task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write operations brief for the agent to read
cat > /home/ga/Documents/QGC/cargo_mission_brief.txt << 'BRIEF'
EMERGENCY MEDICAL CARGO DROP - FLIGHT BRIEF
=============================================
Date: 2026-03-09
Cargo: Anti-venom (Slung load on 2m tether)

1. PARAMETER TUNING (CRITICAL FOR SLUNG LOAD)
Due to the pendulum effect of the slung payload, standard navigation
accelerations will destabilize the aircraft. You must set the following
parameters in Vehicle Setup > Parameters:
  - WPNAV_SPEED: 300 cm/s
  - WPNAV_ACCEL: 100 cm/s/s

2. MISSION PLAN REQUIREMENTS
Create a new mission plan with the following sequence:
  - Takeoff (Transit altitude: approx 30m)
  - Navigate to the drop zone: Latitude -35.3625, Longitude 149.1640
  - Descend at the drop zone to a Safe Drop Altitude of 5.0m or lower
  - Trigger the payload release mechanism:
      Use "Set Servo" (DO_SET_SERVO)
      Servo Instance (param1): 7
      PWM Value (param2): 1900
  - Return To Launch (RTL)

Save the mission plan to: /home/ga/Documents/QGC/cargo_drop.plan
BRIEF
chown ga:ga /home/ga/Documents/QGC/cargo_mission_brief.txt

# 3. Reset parameters to defaults (WPNAV_SPEED=500, WPNAV_ACCEL=250) so do-nothing gets 0 points
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
            b'WPNAV_SPEED': 500.0,
            b'WPNAV_ACCEL': 250.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL & QGC are running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus and maximize QGC window
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== setup complete ==="