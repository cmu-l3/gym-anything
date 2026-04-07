#!/bin/bash
echo "=== Setting up bridge_inspection_lidar_avoidance task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the sensor integration manifest
cat > /home/ga/Documents/QGC/sensor_manifest.txt << 'MANIFEST'
HARDWARE INTEGRATION MANIFEST
Project: Highway Viaduct Inspection Drone
Date: 2026-03-10
Technician: Surveying & Mapping Dept.

=== OVERVIEW ===
This vehicle is equipped with dual LightWare I2C LiDARs to prevent collisions
with the bridge ceiling above and the ground below. The obstacle avoidance
system must be explicitly configured in the flight controller before flight.

=== REQUIRED PARAMETERS ===
Please navigate to QGroundControl -> Vehicle Setup -> Parameters
and set the following 9 parameters:

DOWNWARD SENSOR (RNGFND1):
- RNGFND1_TYPE = 8      (LightWare I2C)
- RNGFND1_ORIENT = 25   (Downward orientation)
- RNGFND1_MAX_CM = 5000 (Maximum reliable range is 50 meters)

UPWARD SENSOR (RNGFND2):
- RNGFND2_TYPE = 8      (LightWare I2C)
- RNGFND2_ORIENT = 24   (Upward orientation)
- RNGFND2_MAX_CM = 1500 (Maximum reliable range is 15 meters)

PROXIMITY AVOIDANCE LOGIC:
- PRX1_TYPE = 4         (Use RangeFinders as the proximity source)
- AVOID_ENABLE = 1      (Enable Proximity Avoidance bitmask)
- AVOID_MARGIN = 2.50   (Stop 2.5 meters away from the ceiling/ground)

IMPORTANT:
Make sure to search for each parameter exactly as written above.
If prompted, confirm the parameter save. The flight controller
applies these dynamically.
MANIFEST

chown ga:ga /home/ga/Documents/QGC/sensor_manifest.txt

# 3. Reset target parameters to incorrect defaults so "do nothing" = 0 pts
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
        
        # Reset parameters to incorrect/factory defaults
        defaults = {
            b'RNGFND1_TYPE': 0.0,
            b'RNGFND1_ORIENT': 0.0,     # Default is usually 25, we force 0 so agent must change it
            b'RNGFND1_MAX_CM': 700.0,
            b'RNGFND2_TYPE': 0.0,
            b'RNGFND2_ORIENT': 0.0,
            b'RNGFND2_MAX_CM': 700.0,
            b'PRX1_TYPE': 0.0,
            b'AVOID_ENABLE': 0.0,
            b'AVOID_MARGIN': 2.00,
        }
        
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory/incorrect defaults.")
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

echo "=== bridge_inspection_lidar_avoidance task setup complete ==="
echo "Manifest: /home/ga/Documents/QGC/sensor_manifest.txt"