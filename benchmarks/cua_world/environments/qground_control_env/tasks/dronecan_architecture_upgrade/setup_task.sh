#!/bin/bash
echo "=== Setting up dronecan_architecture_upgrade task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write engineering work order manifest
cat > /home/ga/Documents/QGC/dronecan_upgrade_manifest.txt << 'MANIFESTDOC'
==================================================
HARDWARE UPGRADE MANIFEST - DRONECAN INTEGRATION
Airframe: Quadcopter Heavy Lift (Custom)
Work Order: WO-2026-084
Date: 2026-03-10
==================================================

BACKGROUND:
This airframe is being upgraded from legacy analog/PWM signaling to a full
DroneCAN (UAVCAN) architecture to eliminate EMI issues during high-power
climbs. The I2C GPS and analog power module have been physically replaced
with two Here3+ CAN GPS units and a Mauch CAN power monitor.

REQUIRED PARAMETER CHANGES:
The flight controller must be configured to initialize the CAN buses and 
look for DroneCAN peripherals instead of legacy ones.

Please use QGroundControl (Vehicle Setup > Parameters) to set the 
following 8 parameters exactly:

[ CAN Bus Initialization ]
CAN_P1_DRIVER = 1    (Enable CAN bus 1)
CAN_P2_DRIVER = 2    (Enable CAN bus 2)
CAN_D1_PROTOCOL = 1  (Set port 1 to DroneCAN protocol)
CAN_D2_PROTOCOL = 1  (Set port 2 to DroneCAN protocol)

[ Peripheral Assignments ]
GPS1_TYPE = 9        (Set primary GPS port to expect DroneCAN)
GPS2_TYPE = 9        (Set secondary GPS port to expect DroneCAN)
BATT_MONITOR = 8     (Set battery monitor to DroneCAN telemetry)
NTF_LED_TYPES = 231  (Enable DroneCAN LED routing bitmask)

NOTE: Parameters take effect immediately upon saving in QGC.
MANIFESTDOC

chown ga:ga /home/ga/Documents/QGC/dronecan_upgrade_manifest.txt

# 3. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset all target parameters to legacy/factory defaults
# This ensures that "do nothing" scores 0 points.
echo "--- Resetting parameters to legacy defaults ---"
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
        
        # Reset to legacy/wrong defaults
        defaults = {
            b'CAN_P1_DRIVER': 0.0,
            b'CAN_P2_DRIVER': 0.0,
            b'CAN_D1_PROTOCOL': 0.0,
            b'CAN_D2_PROTOCOL': 0.0,
            b'GPS1_TYPE': 1.0,     # 1 = AUTO/I2C
            b'GPS2_TYPE': 0.0,     # 0 = None
            b'BATT_MONITOR': 4.0,  # 4 = Analog
            b'NTF_LED_TYPES': 199.0 # Standard default bitmask
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters successfully reset to legacy defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure QGC is running, maximize and focus
echo "--- Checking QGroundControl ---"
ensure_qgc_running
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== dronecan_architecture_upgrade task setup complete ==="
echo "Manifest: /home/ga/Documents/QGC/dronecan_upgrade_manifest.txt"