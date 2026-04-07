#!/bin/bash
set -euo pipefail
echo "=== Setting up pipeline_corridor_inspection_deployment task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the operational deployment package (reference document)
cat > /home/ga/Documents/QGC/pipeline_ops_package.txt << 'OPSDOC'
THERMAGAS INSPECTIONS AG — OPERATIONAL DEPLOYMENT PACKAGE
==========================================================
Pipeline Section: GR-ZH-0447 (Greifensee Lateral)
Date: 2026-03-20
Classification: BVLOS Category-Specific (CH-STS-01)
Pilot-in-Command: TBD

1. PIPELINE ROUTE (WGS84, corridor centerline)
   The corridor scan must follow these centerline waypoints:
   Start:  47.3920 N,  8.5380 E  (Valve Station VS-12)
   WP-A:   47.3940 N,  8.5410 E  (Road crossing RP-44)
   WP-B:   47.3965 N,  8.5445 E  (Stream crossing, marker post)
   WP-C:   47.3985 N,  8.5470 E  (Agricultural field boundary)
   End:    47.4010 N,  8.5500 E  (Valve Station VS-13)

   Corridor survey width: 30 meters (15 m each side of centerline)
   Total route length: approximately 1.2 km

2. THERMAL CAMERA — FLIR Vue Pro R 640
   Sensor dimensions: 10.88 mm x 8.70 mm
   Image resolution:  640 x 512 pixels
   Focal length:      13.0 mm
   Target GSD:        6.0 cm/pixel
   Required flight altitude: Calculate from sensor specs and target GSD
     Formula: Altitude = (GSD_m x Focal_mm x ImageWidth_px) / SensorWidth_mm
   Frontal overlap:   75%
   Side overlap:      65%
   Trigger mode:      Hover-and-capture (thermal stabilization)
   Turnaround distance: 20 meters

3. VEHICLE PARAMETERS (configure before programming geofence)
   Set the following in Vehicle Setup > Parameters:
   - WP_SPD:       4    (4 m/s — reduced for thermal image quality)
   - WP_ACC:       1.5  (gentle acceleration for stable imaging)
   - RTL_ALT_M:    60   (60 m return altitude, clears all corridor obstacles)
   - FENCE_ENABLE: 1    (required for BVLOS — activates geofence)
   - FENCE_ACTION: 1    (RTL on geofence breach)

4. OPERATIONAL GEOFENCE
   Switch to the Fence tab in Plan view to configure the geofence.

   Inclusion boundary (polygon encompassing corridor with buffer):
     Vertex 1 (SW): 47.3910 N, 8.5370 E
     Vertex 2 (SE): 47.3910 N, 8.5510 E
     Vertex 3 (NE): 47.4020 N, 8.5510 E
     Vertex 4 (NW): 47.4020 N, 8.5370 E

   Exclusion zone:
     Greifensee Water Treatment Facility
     Center: 47.3955 N, 8.5430 E
     Radius: 80 meters
     Reason: Active chlorine gas storage — mandatory no-fly

5. EMERGENCY LANDING ZONES (Rally Points)
   Switch to the Rally tab in Plan view.
   Rally Point 1: 47.3930 N, 8.5395 E, altitude 40 m
     (Gravel lot adjacent to VS-12, clear of overhead lines)
   Rally Point 2: 47.3995 N, 8.5485 E, altitude 40 m
     (Cleared agricultural field near VS-13)

6. MISSION STRUCTURE
   The complete plan must include:
   - Takeoff command
   - Corridor scan pattern along the pipeline route (Section 1-2)
   - Return-to-launch
   - Geofence (inclusion + exclusion from Section 4)
   - Rally points (from Section 5)

   You MUST use the Corridor Scan pattern (Plan View > Pattern > Corridor Scan).
   Do NOT use a Survey or simple waypoints for the pipeline route.

   Save complete plan to: /home/ga/Documents/QGC/pipeline_inspection.plan
OPSDOC

chown ga:ga /home/ga/Documents/QGC/pipeline_ops_package.txt

# 3. Ensure SITL is running (needed for parameter reset)
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target parameters to incorrect defaults via pymavlink
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
            b'WP_SPD':       10.0,    # target is 4.0
            b'WP_ACC':       2.5,     # target is 1.5
            b'RTL_ALT_M':    15.0,    # target is 60.0
            b'FENCE_ENABLE': 0.0,     # target is 1
            b'FENCE_ACTION': 0.0,     # target is 1
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to incorrect defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Remove any pre-existing output files (BEFORE recording timestamp)
rm -f /home/ga/Documents/QGC/pipeline_inspection.plan

# 6. Record task start time
date +%s > /tmp/task_start_time

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

echo "=== pipeline_corridor_inspection_deployment task setup complete ==="
echo "Ops package: /home/ga/Documents/QGC/pipeline_ops_package.txt"
echo "Expected output: /home/ga/Documents/QGC/pipeline_inspection.plan"
