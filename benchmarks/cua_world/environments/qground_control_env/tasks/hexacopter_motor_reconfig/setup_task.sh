#!/bin/bash
echo "=== Setting up hexacopter_motor_reconfig task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the manufacturer's airframe specification sheet
cat > /home/ga/Documents/QGC/hexframe_spec.txt << 'SPECDOC'
AGRI-DRONE SYSTEMS GMBH
Airframe Integration Specification Sheet
Model: HexaLift-AG V2 (Multispectral Sensing Config)
Date: 2026-03-09

=== VEHICLE OVERVIEW ===
The HexaLift-AG V2 is a heavy-lift hexacopter designed to carry a MicaSense
RedEdge-MX multispectral camera. The vehicle uses a 6S LiPo power system.
Before maiden flight, the ArduCopter flight controller MUST be configured
with the following parameters to ensure stable flight and proper motor sync.

=== REQUIRED PARAMETERS ===

[FRAME]
FRAME_CLASS      = 2        (Sets the frame type to Hexacopter. The default 1/Quad will crash)

[BATTERY & VOLTAGE COMPENSATION]
We use a 16 Ah 6S LiPo battery. Voltage compensation must be enabled.
MOT_BAT_VOLT_MAX = 25.2     (6S fully charged voltage)
MOT_BAT_VOLT_MIN = 19.8     (6S critically low voltage limit)
BATT_CAPACITY    = 16000    (16 Ah capacity in mAh)

[MOTOR SPIN THRESHOLDS]
To prevent sync issues on these large 18-inch props, adjust the spin thresholds:
MOT_SPIN_ARM     = 0.08     (Slightly lower than default to prevent aggressive jerks on arm)
MOT_SPIN_MIN     = 0.12     (Minimum safe operating spin threshold)

[THRUST CURVE & HOVER]
MOT_THST_EXPO    = 0.55     (Thrust curve exponent for our specific ESC/motor combo)
MOT_THST_HOVER   = 0.42     (The heavier hex frame hovers at approx 42% throttle)

=== INSTRUCTIONS ===
1. Open QGroundControl and connect to the vehicle.
2. Go to Vehicle Setup (wrench icon) > Parameters.
3. Search for each parameter above and set it to the specified value.
4. If QGC warns that a reboot is required, simply click "Ok" to acknowledge (the parameter is still saved).
SPECDOC

chown ga:ga /home/ga/Documents/QGC/hexframe_spec.txt

# 3. Reset all target parameters to factory defaults (quad profile)
# This ensures that a "do-nothing" approach scores 0
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
        
        # Reset to known defaults that differ from the hexacopter required values
        defaults = {
            b'FRAME_CLASS': 1.0,           # Quad
            b'MOT_SPIN_ARM': 0.10,         # Default 0.10
            b'MOT_SPIN_MIN': 0.15,         # Default 0.15
            b'MOT_BAT_VOLT_MAX': 0.0,      # Default 0 (disabled)
            b'MOT_BAT_VOLT_MIN': 0.0,      # Default 0 (disabled)
            b'MOT_THST_EXPO': 0.65,        # Default 0.65
            b'MOT_THST_HOVER': 0.35,       # Default 0.35
            b'BATT_CAPACITY': 3300.0,      # Default 3300 mAh
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to default quad profile")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
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

echo "=== hexacopter_motor_reconfig task setup complete ==="
echo "Spec Sheet: /home/ga/Documents/QGC/hexframe_spec.txt"