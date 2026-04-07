#!/bin/bash
echo "=== Setting up dual_gps_yaw_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the integration work order document
cat > /home/ga/Documents/QGC/dual_gps_specs.txt << 'SPECDOC'
INTEGRATION WORK ORDER: DUAL GPS & GPS-FOR-YAW RETROFIT
Vehicle ID: HEX-HL-04 (Heavy-Lift Hexacopter)
Task: Configure Dual GPS blending and GPS-derived Yaw due to high EMI environment.

REQUIREMENTS:
1. Enable the secondary GPS unit. 
   -> Set GPS_TYPE2 to 1 (Auto).
   
2. Configure GPS blending to optimize satellite usage. 
   -> Set GPS_AUTO_SWITCH to 2 (Blend).
   
3. Switch the EKF3 estimator's primary yaw source to the GPS. 
   -> Set EK3_SRC1_YAW to 2 (GPS).
   
4. Completely disable the magnetic compass to prevent EMI toilet-bowling. 
   -> Set COMPASS_ENABLE to 0.

5. Configure Antenna Offsets:
   The flight controller is at the Center of Gravity (CG). You must input the
   physical antenna offsets in meters using the ArduPilot NED coordinate system
   (North/Forward = +X, East/Right = +Y, Down = +Z).

   - Main GPS (GPS1) is mounted 35 cm behind the CG, and 20 cm above the CG.
     -> Set GPS_POS1_X and GPS_POS1_Z accordingly.
     
   - Aux GPS (GPS2) is mounted 35 cm ahead of the CG, and 20 cm above the CG.
     -> Set GPS_POS2_X and GPS_POS2_Z accordingly.

   (Note: Both antennas are centered on the Y-axis, so Y offsets remain 0.
    Be careful with the Z-axis: in the NED frame, Down is positive!)
    
Set ALL 8 parameters before clearing the vehicle for test flight.
SPECDOC

chown ga:ga /home/ga/Documents/QGC/dual_gps_specs.txt

# 3. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target parameters to default values to ensure clean start
# This guarantees that a "do-nothing" agent gets a score of 0
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
        
        # Reset to known defaults (single GPS, compass on, zero offsets)
        defaults = {
            b'GPS_TYPE2': 0.0,
            b'GPS_AUTO_SWITCH': 1.0,
            b'EK3_SRC1_YAW': 1.0,
            b'COMPASS_ENABLE': 1.0,
            b'GPS_POS1_X': 0.0,
            b'GPS_POS2_X': 0.0,
            b'GPS_POS1_Z': 0.0,
            b'GPS_POS2_Z': 0.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== dual_gps_yaw_config task setup complete ==="
echo "Work order: /home/ga/Documents/QGC/dual_gps_specs.txt"