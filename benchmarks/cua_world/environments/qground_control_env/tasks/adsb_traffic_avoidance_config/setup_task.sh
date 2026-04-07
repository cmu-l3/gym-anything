#!/bin/bash
echo "=== Setting up adsb_traffic_avoidance_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the mandate document for the agent to read
cat > /home/ga/Documents/QGC/caa_adsb_mandate.txt << 'MANDATE'
CAA BVLOS TRAFFIC AVOIDANCE MANDATE (CORRIDOR 7A)
=================================================
To operate in Corridor 7A, the UAV must be configured to detect and avoid manned aircraft using ADS-B In.

Mandatory System Configuration:
1. The onboard ADS-B receiver must be ENABLED.
2. The active traffic avoidance system must be ENABLED.

Separation Minimums (Warning Zone):
- Horizontal Warning Radius: 1500 meters
- Vertical Warning Radius: 300 meters

Separation Minimums (Breach/Action Zone):
- Horizontal Breach Radius: 500 meters
- Vertical Breach Radius: 150 meters

Required Automated Response:
- In the event of a traffic breach, the avoidance action must be set to LOITER (Action ID: 2).
MANDATE

chown ga:ga /home/ga/Documents/QGC/caa_adsb_mandate.txt

# 3. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target parameters to incorrect defaults so "do-nothing" scores 0
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
        
        # Reset to known defaults that differ from the required mandate
        defaults = {
            b'ADSB_ENABLE': 0.0,
            b'AVD_ENABLE': 0.0,
            b'AVD_W_DIST_XY': 1000.0,
            b'AVD_W_DIST_Z': 100.0,
            b'AVD_F_DIST_XY': 300.0,
            b'AVD_F_DIST_Z': 50.0,
            b'AVD_F_ACTION': 0.0,
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

# 5. Remove any pre-existing parameter backups
rm -f /home/ga/Documents/QGC/adsb_configured.params

# 6. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time

# 7. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== adsb_traffic_avoidance_config task setup complete ==="
echo "Mandate document: /home/ga/Documents/QGC/caa_adsb_mandate.txt"