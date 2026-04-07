#!/bin/bash
echo "=== Setting up slung_payload_mag_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the operations brief
cat > /home/ga/Documents/QGC/mag_survey_protocol.txt << 'PROTODOC'
SLUNG PAYLOAD MAGNETIC SURVEY PROTOCOL
Project: Iron Ore Seam Detection (Block 4)
Sensor: Cesium Vapor Magnetometer (5m slung cable)

=== VEHICLE KINEMATIC TUNING ===
A 5-meter slung payload will swing violently and destabilize the aircraft if default accelerations are used.
You MUST set the following parameters in Vehicle Setup > Parameters:

  WPNAV_SPEED = 300      (Maximum Waypoint Speed: 300 cm/s = 3 m/s)
  WPNAV_ACCEL = 100      (Waypoint Acceleration: 100 cm/s/s = 1 m/s/s)
  ANGLE_MAX   = 2000     (Maximum Lean Angle: 2000 centi-degrees = 20 degrees)

(Ensure these are set on the vehicle before flight. Do not use default values.)

=== MISSION PLAN GEOMETRY ===
Create a new mission plan with the following sequence:

1. Takeoff
   - Altitude: 40 m

2. Sensor Warm-up Delay
   - Insert a "Delay" command immediately after takeoff.
   - Delay time: 60 seconds.
   - (The Cesium sensor requires 60s of undisturbed flight to acquire optical lock).

3. Survey Pattern
   - Altitude: 40 m
   - Spacing: 15 m
   - Turnaround Distance: 30 m (CRITICAL: A wide 30m turnaround allows the 5m pendulum to settle before the next transect).
   - Draw the polygon over any clear area near the launch point.

4. Return to Launch (RTL)
   - Ensure an RTL command is at the end of the mission.

=== OUTPUT ===
Save the completed mission plan to:
/home/ga/Documents/QGC/slung_mag_survey.plan
PROTODOC

chown ga:ga /home/ga/Documents/QGC/mag_survey_protocol.txt

# 3. Reset target parameters to unsafe defaults so do-nothing = 0 pts
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # warm-up: let MAVLink channel stabilize
        
        # Reset to aggressive defaults that differ from the required slung payload tuning
        defaults = {
            b'WPNAV_SPEED': 500.0,
            b'WPNAV_ACCEL': 250.0,
            b'ANGLE_MAX': 3000.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to aggressive defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any existing plan files
rm -f /home/ga/Documents/QGC/slung_mag_survey.plan

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 7. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== slung_payload_mag_survey task setup complete ==="
echo "Protocol: /home/ga/Documents/QGC/mag_survey_protocol.txt"