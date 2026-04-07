#!/bin/bash
echo "=== Setting up indoor_navigation_sensor_setup task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the integration work order
cat > /home/ga/Documents/QGC/integration_work_order.txt << 'WORKORDER'
HARDWARE INTEGRATION WORK ORDER
Project: Automated Warehouse Inventory UAV
Date: 2026-03-10
Engineer: UAV Integration Team

=== SYSTEM OVERVIEW ===
This vehicle will operate indoors in a GPS-denied environment. We have physically
installed two new sensors that must be configured in ArduCopter firmware to 
provide state estimation via EKF3.

=== SENSOR 1: DOWNWARD LiDAR (Altitude) ===
Hardware: Benewake TFmini (Serial version)
Wiring: Connected to TELEM2 port on the flight controller.

Required Parameter Changes:
- RNGFND1_TYPE = 20 (Driver for Benewake TFmini - Serial)
- RNGFND1_MAX_CM = 800 (Sensor maximum range is 8 meters)
- RNGFND1_MIN_CM = 10 (Sensor minimum range is 10 centimeters)
- SERIAL2_PROTOCOL = 9 (Protocol for Rangefinder)
- SERIAL2_BAUD = 115 (TFmini communicates at 115200 baud)

=== SENSOR 2: OPTICAL FLOW (Horizontal Velocity) ===
Hardware: CX-OF Optical Flow Sensor
Wiring: I2C bus

Required Parameter Changes:
- FLOW_TYPE = 2 (Driver for CX-OF sensor)

=== EKF3 STATE ESTIMATION CONFIGURATION ===
Since GPS is unavailable and indoor HVAC systems cause Barometer drift, we must
tell the Extended Kalman Filter (EKF3) to use our new sensors for navigation.

Required Parameter Changes:
- EK3_SRC1_VELXY = 5 (Set horizontal velocity source to OpticalFlow instead of GPS)
- EK3_SRC1_POSZ = 2 (Set vertical position source to RangeFinder instead of Baro)

=== INSTRUCTIONS ===
Open QGroundControl and navigate to Vehicle Setup > Parameters.
Use the search bar to find and modify all 8 parameters listed above.
The parameters are saved immediately to the vehicle upon setting.
WORKORDER

chown ga:ga /home/ga/Documents/QGC/integration_work_order.txt

# 3. Reset parameters to factory defaults (different from targets)
python3 << 'PYEOF'
import time
import sys

try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # warm-up: let MAVLink channel stabilize
        
        # Reset to known defaults that differ from the target values
        defaults = {
            b'RNGFND1_TYPE': 0.0,
            b'RNGFND1_MAX_CM': 700.0,
            b'RNGFND1_MIN_CM': 20.0,
            b'SERIAL2_PROTOCOL': 2.0,  # Default is MAVLink 2
            b'SERIAL2_BAUD': 57.0,     # Default is 57600
            b'FLOW_TYPE': 0.0,
            b'EK3_SRC1_VELXY': 3.0,    # Default is GPS
            b'EK3_SRC1_POSZ': 1.0,     # Default is Baro
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

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== indoor_navigation_sensor_setup task setup complete ==="
echo "Work order: /home/ga/Documents/QGC/integration_work_order.txt"