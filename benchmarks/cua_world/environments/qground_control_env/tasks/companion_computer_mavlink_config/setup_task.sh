#!/bin/bash
echo "=== Setting up companion_computer_mavlink_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory and write the integration specification
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

cat > /home/ga/Documents/QGC/companion_integration_spec.txt << 'SPECDOC'
COMPANION COMPUTER INTEGRATION SPECIFICATION
Hardware: NVIDIA Jetson Orin Nano
Target Port: TELEM2 (SERIAL2)
Date: 2026-03-09

=== OVERVIEW ===
The AI visual target tracking node requires a high-bandwidth MAVLink 2 connection 
with specific high-frequency stream rates. ArduPilot's default telemetry port 
settings (57600 baud, 1-2 Hz stream rates) are insufficient and will cause the 
tracking node to fail due to missing data.

=== REQUIRED PARAMETERS ===

Using QGroundControl (Vehicle Setup > Parameters), search for and configure 
the following 9 parameters:

-- SERIAL PORT CONFIGURATION --
SERIAL2_PROTOCOL : 2    (Configures port to MAVLink 2)
SERIAL2_BAUD     : 921  (Configures baud rate to 921600)

-- MAVLINK STREAM RATES (SR2) --
The Jetson is connected to TELEM2, which corresponds to the SR2 parameter group.
Set the following rates (in Hz):

SR2_POSITION     : 50   (Local/Global position data at 50Hz)
SR2_EXTRA1       : 50   (Attitude data at 50Hz)
SR2_EXTRA2       : 20   (VFR_HUD data at 20Hz)
SR2_EXTRA3       : 10   (Secondary sensor data at 10Hz)
SR2_RC_CHAN      : 20   (RC override data at 20Hz)
SR2_EXT_STAT     : 5    (Extended status / Battery data at 5Hz)
SR2_RAW_SENS     : 10   (Raw IMU sensor data at 10Hz)

Ensure all 9 parameters are successfully saved to the flight controller.
SPECDOC

chown ga:ga /home/ga/Documents/QGC/companion_integration_spec.txt

# 2. Reset all target parameters to 0 (disabled) via pymavlink
# This prevents agents from passing by doing nothing.
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
        
        defaults = {
            b'SERIAL2_PROTOCOL': 0.0,
            b'SERIAL2_BAUD': 0.0,
            b'SR2_POSITION': 0.0,
            b'SR2_EXTRA1': 0.0,
            b'SR2_EXTRA2': 0.0,
            b'SR2_EXTRA3': 0.0,
            b'SR2_RC_CHAN': 0.0,
            b'SR2_EXT_STAT': 0.0,
            b'SR2_RAW_SENS': 0.0,
        }
        
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters successfully reset to 0 to prevent gaming.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 3. Record task start time
date +%s > /tmp/task_start_time

# 4. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 5. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== companion_computer_mavlink_config task setup complete ==="
echo "Specification: /home/ga/Documents/QGC/companion_integration_spec.txt"