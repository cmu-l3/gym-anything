#!/bin/bash
echo "=== Setting up mountain_terrain_rtl_failsafe task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the operations safety brief
cat > /home/ga/Documents/QGC/mountain_ops_brief.txt << 'OPSBRIEF'
MOUNTAIN OPERATIONS SAFETY BRIEF
Mission: Geological Survey, Sector Echo (Steep Valley)
Vehicle: ArduCopter (SITL Simulation)
Date: 2026-03-10

=== CRITICAL TERRAIN HAZARD ===
This survey takes place in a steep, mountainous valley. If the radio link is lost, the standard Return-to-Launch (RTL) profile will cause the vehicle to crash directly into the mountainside (Controlled Flight Into Terrain).

Before the vehicle is cleared for launch, you MUST configure the following 6 parameters using QGroundControl (Vehicle Setup > Parameters).

=== REQUIRED PARAMETERS ===

1. TERRAIN_ENABLE
   Description: Enable terrain data subsystem for altitude reference.
   Required Value: 1 (Enabled)

2. RTL_ALT
   Description: The primary RTL transit altitude.
   Required Value: 20000
   Note: ArduPilot stores this in centimeters. 20000 cm = 200 meters.

3. RTL_CLIMB_MIN
   Description: Minimum altitude the vehicle must climb before returning, ensuring it clears immediate obstacles like tall pines.
   Required Value: 5000
   Note: 5000 cm = 50 meters.

4. RTL_SPEED
   Description: Horizontal transit speed during RTL. Needs to be reduced for safety in high-wind mountain conditions.
   Required Value: 800
   Note: 800 cm/s = 8 m/s.

5. RTL_ALT_FINAL
   Description: The final hover altitude above the launch point before auto-landing or manual takeover.
   Required Value: 1000
   Note: 1000 cm = 10 meters hover.

6. FS_GCS_ENABLE
   Description: Ground Control Station heartbeat failsafe. Crucial to trigger the RTL if the radio link is blocked by a ridge.
   Required Value: 1 (Trigger RTL on link loss)

=== HOW TO CONFIGURE ===
1. Open QGroundControl and wait for the vehicle to connect.
2. Click the 'Q' icon (top left) > Vehicle Setup > Parameters.
3. Search for each parameter by name.
4. Click its row, type the required value, and click "Save" or press Enter.
5. The vehicle will update immediately via MAVLink.
OPSBRIEF

chown ga:ga /home/ga/Documents/QGC/mountain_ops_brief.txt

# 3. Reset the 6 target parameters to defaults (which differ from required values)
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # Wait for connection to stabilize
        # Default values intentionally differ from required safety settings
        defaults = {
            b'TERRAIN_ENABLE': 0.0,
            b'RTL_ALT': 1500.0,
            b'RTL_CLIMB_MIN': 0.0,
            b'RTL_SPEED': 0.0,
            b'RTL_ALT_FINAL': 0.0,
            b'FS_GCS_ENABLE': 0.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters successfully reset to unsafe defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

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

echo "=== mountain_terrain_rtl_failsafe task setup complete ==="
echo "Operations Brief: /home/ga/Documents/QGC/mountain_ops_brief.txt"