#!/bin/bash
echo "=== Setting up autonomous_forest_obstacle_avoidance task ==="

source /workspace/scripts/task_utils.sh

# 1. Create necessary directories and set permissions
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the payload integration specification document
cat > /home/ga/Documents/QGC/lidar_integration_spec.txt << 'SPECDOC'
HARDWARE INTEGRATION SPECIFICATION: SUB-CANOPY LiDAR
Project: Forest Undergrowth Mapping - Sector 4
Vehicle: AC-SITL-008
Date: 2026-03-10

=== OVERVIEW ===
A 360-degree obstacle avoidance LiDAR has been mechanically mounted and connected 
to the Telem2 port (Serial 2) on the flight controller. To prevent crashes during 
sub-canopy autonomous waypoint flights, you must configure the flight controller 
to communicate with the sensor and enable the BendyRuler path-planning algorithm.

=== REQUIRED PARAMETER CONFIGURATION ===
Use QGroundControl (Vehicle Setup > Parameters) to apply the following 8 changes.

--- SENSOR COMMUNICATION ---
1. PRX1_TYPE = 5
   (Sets the primary proximity sensor to RPLidar/Lidar360 protocol)

2. SERIAL2_PROTOCOL = 11
   (Sets Telem2 port to expect Lidar360 data, overriding the MAVLink default)

3. SERIAL2_BAUD = 115
   (Configures the port baud rate to 115200)

--- OBSTACLE AVOIDANCE (BendyRuler) ---
4. OA_TYPE = 1
   (Enables the BendyRuler obstacle avoidance algorithm. 0=Disabled)

5. OA_BR_LOOKAHEAD = 8
   (Sets the lookahead distance for path planning to 8 meters)

6. OA_MARGIN_MAX = 2.5
   (Forces the drone to keep a minimum 2.5 meter margin from detected trees/obstacles)

--- NAVIGATION BEHAVIOR ---
7. AVOID_ENABLE = 2
   (Configures the avoidance action. Value 2 enables Proximity Avoidance)

8. WPNAV_SPEED = 300
   (Reduces maximum waypoint navigation speed to 300 cm/s to give the drone 
    sufficient reaction time when encountering dense foliage)

Note: All parameters take effect immediately upon being set. Ensure you configure 
all 8 parameters to pass the integration audit.
SPECDOC

chown ga:ga /home/ga/Documents/QGC/lidar_integration_spec.txt

# 3. Reset parameters to defaults (different from targets) via pymavlink
# This ensures that doing nothing yields a score of 0
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # Let MAVLink stabilize
        
        # Factory defaults (incorrect for the given setup)
        defaults = {
            b'PRX1_TYPE': 0.0,
            b'SERIAL2_PROTOCOL': 2.0,
            b'SERIAL2_BAUD': 57.0,
            b'OA_TYPE': 0.0,
            b'OA_BR_LOOKAHEAD': 5.0,
            b'OA_MARGIN_MAX': 2.0,
            b'AVOID_ENABLE': 3.0,
            b'WPNAV_SPEED': 500.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory defaults (obstacle avoidance disabled).")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL and QGC are running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus, maximize, and dismiss startup dialogues
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== autonomous_forest_obstacle_avoidance task setup complete ==="
echo "Integration Spec: /home/ga/Documents/QGC/lidar_integration_spec.txt"