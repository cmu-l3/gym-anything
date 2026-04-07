#!/bin/bash
echo "=== Setting up tethered_drone_failsafe_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the standard operating procedure manual
cat > /home/ga/Documents/QGC/tether_ops_manual.txt << 'MANUAL'
TETHERED DRONE OPERATIONS MANUAL
Vehicle: AC-SITL-007 (Tethered Config)
Date: 2026-03-10

=== CRITICAL FAILSAFE CONFIGURATION ===

This vehicle is operating on a 50-meter physical power/data tether.
Default free-flight failsafes will DESTROY the vehicle and snap the tether.
You MUST configure the following parameters in QGroundControl (Vehicle Setup > Parameters) before flight.

1. FENCE_ALT_MAX
   Description: Maximum altitude fence.
   Requirement: 45
   (Provides 5 meters of tether slack)

2. FENCE_RADIUS
   Description: Maximum lateral distance.
   Requirement: 10
   (Keeps the drone directly above the ground station)

3. FENCE_ENABLE
   Description: Turn on the geofence.
   Requirement: 1
   (0 is disabled, 1 is enabled)

4. FENCE_ACTION
   Description: Failsafe action when fence is breached.
   Requirement: 3
   (Standard is RTL. For tether, we must use 3 which is Land/Return without climbing)

5. RTL_ALT
   Description: Return to Launch altitude.
   Requirement: 0
   (Default climbs to 15m. 0 ensures it returns/lands at current altitude)

6. WPNAV_SPEED_UP
   Description: Ascent speed.
   Requirement: 100
   (Default ascends too fast for the spool motor. 100 cm/s is safe)

7. FS_BATT_ENABLE (or BATT_FS_LOW_ACT depending on firmware)
   Description: Low battery failsafe.
   Requirement: 0
   (Ground power makes battery voltage fluctuate. Must be 0 to disable)

=== CONFIGURATION EXPORT ===

After setting all 7 parameters, you MUST save the configuration.
1. In the QGC Parameters screen, click "Tools" (top right of the parameters page).
2. Click "Save to file".
3. Save the file exactly as: /home/ga/Documents/QGC/tether_config.params
MANUAL

chown ga:ga /home/ga/Documents/QGC/tether_ops_manual.txt

# 3. Reset all target parameters to bad defaults so doing nothing yields 0 pts
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
        # Reset to known defaults that violate the tether requirements
        defaults = {
            b'FENCE_ALT_MAX': 100.0,
            b'FENCE_RADIUS': 300.0,
            b'FENCE_ENABLE': 0.0,
            b'FENCE_ACTION': 1.0,
            b'RTL_ALT': 1500.0,
            b'WPNAV_SPEED_UP': 250.0,
            b'FS_BATT_ENABLE': 1.0,
            b'BATT_FS_LOW_ACT': 1.0
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing config file
rm -f /home/ga/Documents/QGC/tether_config.params

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL and QGC running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus, maximize, clear dialogs
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== tethered_drone_failsafe_config task setup complete ==="
echo "Manual: /home/ga/Documents/QGC/tether_ops_manual.txt"