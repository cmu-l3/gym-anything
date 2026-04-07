#!/bin/bash
echo "=== Setting up high_altitude_density_tuning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory for the report
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the engineering report
cat > /home/ga/Documents/QGC/aerodynamic_report.txt << 'REPDOC'
FLIGHT ENGINEERING REPORT: HIGH ALTITUDE AERODYNAMIC RECONFIGURATION
Airframe: Heavy-Lift Survey Hexacopter (AC-HL-04)
Deployment Location: Los Pelambres, Chile
Elevation: 4,500m ASL (14,700 ft)
Date: 2026-03-10

SUMMARY
Due to the ~40% reduction in air density at the deployment elevation, the vehicle requires immediate aerodynamic parameter reconfiguration. Using sea-level defaults will result in propeller stall during descent, motor saturation, and potential loss of attitude control.

REQUIRED PARAMETER UPDATES
Please update the following parameters via QGroundControl (Vehicle Setup > Parameters) before the maiden test flight:

1. MOT_THST_HOVER = 0.42
   (Increases the baseline hover thrust expectation for thin air. Default is usually ~0.12-0.20)

2. MOT_HOVER_LEARN = 0
   (Disables hover learning to prevent the controller from adapting poorly during transient turbulent drafts in the Andes)

3. MOT_SPIN_ARM = 0.15
   (Increases arming idle spin to prevent stall in thin air. Default is 0.10)

4. MOT_SPIN_MIN = 0.17
   (Increases the minimum in-flight spin speed. Default is 0.15)

5. ATC_THR_MIX_MAN = 0.1
   (Reduces the manual throttle mix to prioritize attitude control over thrust, preventing flips if motors saturate at high altitude. Default is 0.5)

6. MOT_YAW_HEADROOM = 150
   (Reduces yaw headroom to preserve thrust capacity for roll/pitch. Default is 200)

AUTHORIZATION
Approved by: Lead Flight Dynamics Engineer
REPDOC

chown ga:ga /home/ga/Documents/QGC/aerodynamic_report.txt

# 3. Reset the target parameters to default sea-level values
# This guarantees that "do-nothing" results in 0 points
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
        
        # Reset parameters to known sea-level defaults
        defaults = {
            b'MOT_THST_HOVER': 0.1225,
            b'MOT_HOVER_LEARN': 2.0,
            b'MOT_SPIN_ARM': 0.10,
            b'MOT_SPIN_MIN': 0.15,
            b'ATC_THR_MIX_MAN': 0.5,
            b'MOT_YAW_HEADROOM': 200.0,
        }
        
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to sea-level defaults")
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

echo "=== high_altitude_density_tuning task setup complete ==="
echo "Engineering Report: /home/ga/Documents/QGC/aerodynamic_report.txt"