#!/bin/bash
echo "=== Setting up sar_avalanche_thermal_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the SAR operations brief
cat > /home/ga/Documents/QGC/sar_ops_brief.txt << 'SARDOC'
SAR OPERATIONS BRIEF: AVALANCHE THERMAL SURVEY
Mission ID: SAR-2026-ALPHA
Date: 2026-03-10
Status: URGENT / HIGH PRIORITY

=== SITUATION ===
An avalanche has occurred in the eastern sector. A victim is believed to be buried under shallow snow. A thermal survey is required to detect body heat anomalies.

=== WEATHER CONTINGENCIES ===
High crosswinds (up to 35 km/h) are observed in the valley. You must configure the vehicle parameters BEFORE flight:
1. WEATH_ENABLE: Set to 1 (Enable auto-weathervaning). This allows the drone to automatically yaw its nose into the wind during hover/survey turns, saving critical battery life.
2. RTL_SPEED: Set to 1500 (15 m/s). The standard return speed is too slow to penetrate the expected headwinds.

=== PAYLOAD / CAMERA CONFIGURATION ===
We are using a custom thermal payload: FLIR Vue Pro 640.
You must select "Custom Camera" in the QGC Survey settings and manually enter these exact optical specifications:
- Sensor Width:  10.88 mm
- Sensor Height: 8.16 mm
- Image Width:   640 px
- Image Height:  512 px
- Focal Length:  13.0 mm

=== FLIGHT PARAMETERS ===
To ensure the thermal signatures are detectable and stitchable:
- Survey Altitude: 80 m
- Frontal Overlap: 80%
- Side Overlap:    70%

=== MISSION PLAN INSTRUCTIONS ===
1. Create a Survey pattern (Plan View > Pattern > Survey).
2. Draw a polygon to the EAST of the launch point (at least 4 vertices).
3. Apply the custom camera, altitude, and overlap settings above.
4. Save the plan to: /home/ga/Documents/QGC/avalanche_thermal_search.plan
SARDOC

chown ga:ga /home/ga/Documents/QGC/sar_ops_brief.txt

# 3. Reset parameters to default/incorrect values via pymavlink
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)
        # Reset to defaults so the agent has to change them
        defaults = {
            b'WEATH_ENABLE': 0.0,
            b'RTL_SPEED': 500.0, # 5 m/s, incorrect for this mission
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to default/incorrect values")
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

echo "=== sar_avalanche_thermal_survey task setup complete ==="
echo "Brief: /home/ga/Documents/QGC/sar_ops_brief.txt"