#!/bin/bash
echo "=== Setting up sar_thermal_survey_preparation task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the SAR Operations Plan (reference document the agent must read)
cat > /home/ga/Documents/QGC/sar_operations_plan.txt << 'OPSDOC'
SEARCH AND RESCUE OPERATIONS PLAN
===================================
Mission: Namadgi SAR Thermal Search
Date: 2026-03-20
Classification: URGENT

1. SITUATION
A solo bushwalker (male, 34) was reported overdue at 1830h yesterday.
Last Known Position (LKP): near the Cotter River walking trail, bushland
south of Lake Burley Griffin. Overnight temperature: 4 deg C. Terrain:
eucalyptus woodland with rocky outcrops, elevation 580-640 m.

2. SEARCH AREA
The search area is in the bushland south of the vehicle's current
position. In QGroundControl Plan view, create a Survey pattern polygon
covering an area near the vehicle home position. The exact polygon
shape is secondary to correctly configuring the survey parameters below.

3. AIRCRAFT AND SENSOR
Platform: ArduCopter (SITL commissioning vehicle)
Thermal Camera: FLIR Vue Pro R 640
  - Sensor width:  10.88 mm
  - Sensor height:  8.70 mm
  - Image width:     640 px
  - Image height:    512 px
  - Focal length:   19.0 mm

Under Camera settings in the Survey item, select "Custom Camera" (or
"Manual") and enter the exact sensor details listed above.

4. SURVEY PARAMETERS
  - Altitude:             80 m AGL
  - Frontal overlap:      80 %
  - Side overlap:         70 %
  - Capture mode:         Hover and Capture (stop-and-shoot for thermal clarity)
  - Turnaround distance:  25 m

5. SAFETY CONFIGURATION (ArduPilot Parameters)
Set the following parameters via Vehicle Setup > Parameters:
  - FENCE_ENABLE  = 1      (enable geofence)
  - FENCE_ACTION  = 1      (RTL on breach)
  - FS_GCS_ENABLE = 1      (RTL on GCS link loss)
  - RTL_ALT_M     = 80     (meters, return altitude)
  - WP_SPD        = 4      (m/s, survey speed)

6. RALLY POINT
Emergency landing zone (open paddock with road access):
  Latitude:  -35.3580
  Longitude: 149.1630

Add this as a Rally Point in the Plan view (use the Rally tab).

7. VIDEO FEED
Configure QGroundControl video source in Application Settings > Video:
  Type: RTSP Video Stream
  URL:  rtsp://10.0.1.100:8554/thermal_live

8. DELIVERABLES
Save the following files before launch:
  a. Mission plan:     /home/ga/Documents/QGC/sar_thermal_survey.plan
  b. Parameter export: /home/ga/Documents/QGC/sar_safety_params.params
  c. Mission brief:    /home/ga/Documents/QGC/sar_mission_brief.txt
     The brief must contain:
       - Mission name: "Namadgi SAR Thermal Search"
       - Camera model used
       - Survey altitude
       - Rally point coordinates
       - RTSP URL
       - Confirmation: "All safety parameters configured"
OPSDOC

chown ga:ga /home/ga/Documents/QGC/sar_operations_plan.txt

# 3. Reset ArduPilot parameters to non-target defaults via pymavlink
#    so "do nothing" = 0 points on parameter checks
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762',
                                        source_system=254,
                                        dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # let MAVLink channel stabilize
        defaults = {
            b'FENCE_ENABLE':  0.0,    # target is 1
            b'FENCE_ACTION':  0.0,    # target is 1
            b'FS_GCS_ENABLE': 0.0,    # target is 1
            b'RTL_ALT_M':     15.0,   # target is 80
            b'WP_SPD':        10.0,   # target is 4
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to non-target defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing output files
rm -f /home/ga/Documents/QGC/sar_thermal_survey.plan
rm -f /home/ga/Documents/QGC/sar_safety_params.params
rm -f /home/ga/Documents/QGC/sar_mission_brief.txt

# 5. Record task start time (AFTER deleting stale outputs)
date +%s > /tmp/task_start_time

# 6. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 7. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== sar_thermal_survey_preparation task setup complete ==="
echo "Operations plan: /home/ga/Documents/QGC/sar_operations_plan.txt"
echo "Expected outputs:"
echo "  Plan:   /home/ga/Documents/QGC/sar_thermal_survey.plan"
echo "  Params: /home/ga/Documents/QGC/sar_safety_params.params"
echo "  Brief:  /home/ga/Documents/QGC/sar_mission_brief.txt"
