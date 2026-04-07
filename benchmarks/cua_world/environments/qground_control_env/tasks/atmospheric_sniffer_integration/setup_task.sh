#!/bin/bash
echo "=== Setting up atmospheric_sniffer_integration task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write payload integration brief
cat > /home/ga/Documents/QGC/payload_integration_brief.txt << 'BRIEFDOC'
PAYLOAD INTEGRATION BRIEF: Methane (CH4) Laser Sniffer
Platform: ArduCopter SITL
Date: 2026-03-10
Scientist: Atmospheric Research Division

=== 1. FLIGHT CONTROLLER PARAMETER CONFIGURATION ===
The custom CH4 sniffer communicates via Serial 4 and relies on a Lua script to
parse its proprietary telemetry stream. You MUST configure the following 6
ArduPilot parameters before flight.

SCRIPTING SETUP:
  SCR_ENABLE = 1           (Enables the Lua scripting engine)
  SCR_HEAP_SIZE = 81920    (Allocates 80KB heap for the sniffer parser)

COMMUNICATIONS SETUP:
  SERIAL4_PROTOCOL = 28    (Sets Serial 4 to Scripting protocol)
  SERIAL4_BAUD = 115       (Sets Serial 4 baud rate to 115200)

DATA & STARTUP SETUP:
  LOG_DISARMED = 1         (Allows recording ground calibration data before takeoff)
  BRD_BOOT_DELAY = 3000    (Delays boot by 3000ms to let the laser warm up)

Use QGroundControl > Vehicle Setup > Parameters to search for and set these.
Note: You may need to click "Tools > Reboot Vehicle" after setting SCR_ENABLE,
or just rely on the MAVLink parameter sets if SITL accepts them directly.

=== 2. VERTICAL PROFILE MISSION PLAN ===
Standard mapping surveys are horizontal. We need a VERTICAL column profile to
measure the gas concentration gradient through the boundary layer.

Create a mission with the following sequence:
  1. Takeoff (Altitude: 10 m)
  2. Change Speed (DO_CHANGE_SPEED): Set speed to 1.0 m/s. This slow ascent is
     CRITICAL for the sensor's 1Hz sampling rate to capture vertical resolution.
  3. Waypoint: Place a waypoint directly over the launch area, with an altitude
     of at least 150 m.
  4. Return To Launch (RTL).

Save this mission to:
  /home/ga/Documents/QGC/vertical_profile.plan

Do not begin flight operations. Just complete the integration and planning.
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/payload_integration_brief.txt

# 3. Reset parameters to conflicting defaults
echo "--- Resetting target parameters to defaults ---"
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
        # Defaults distinct from required targets
        defaults = {
            b'SCR_ENABLE': 0.0,
            b'SCR_HEAP_SIZE': 40960.0,
            b'SERIAL4_PROTOCOL': 5.0,
            b'SERIAL4_BAUD': 57.0,
            b'LOG_DISARMED': 0.0,
            b'BRD_BOOT_DELAY': 0.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing mission file
rm -f /home/ga/Documents/QGC/vertical_profile.plan

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL and QGC running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== atmospheric_sniffer_integration task setup complete ==="
echo "Brief: /home/ga/Documents/QGC/payload_integration_brief.txt"