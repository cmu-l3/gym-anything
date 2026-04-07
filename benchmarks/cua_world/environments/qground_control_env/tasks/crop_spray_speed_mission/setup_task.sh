#!/bin/bash
echo "=== Setting up crop_spray_speed_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the spray specification document
cat > /home/ga/Documents/QGC/spray_spec.txt << 'SPECDOC'
PRECISION SPRAY MISSION SPECIFICATION
=====================================
Client: Murray Valley Soybean Cooperative
Date: 2026-03-10
UAV: ArduCopter Hex (Payload: 10L spray tank + Raven DX45 nozzles)
Operator: Agricultural Technician

CHEMICAL APPLICATION REQUIREMENTS:
- Target rate: 15 L/ha
- Nozzle calibration speed: 3 m/s ground speed
- Application altitude: 8 m AGL
- Swath width: 3 m (per pass)

MISSION PROFILE:
- Takeoff altitude: 15 m AGL (relative)
- Transit speed: 8 m/s ground speed
- Spray pass speed: 3 m/s ground speed
- Spray pass altitude: 8 m AGL (relative)
- Return method: RTL (Return to Launch)

FIELD COORDINATES (WGS84, decimal degrees):
  Home/Launch:         -35.3632, 149.1652
  
  Field Entry Point:   -35.3620, 149.1670  (transit at 15m altitude)
  
  Spray Pass 1 Start:  -35.3615, 149.1665  (spray at 8m altitude)
  Spray Pass 1 End:    -35.3615, 149.1690  (spray at 8m altitude)
  Spray Pass 2 Start:  -35.3612, 149.1690  (spray at 8m altitude)
  Spray Pass 2 End:    -35.3612, 149.1665  (spray at 8m altitude)
  
  Field Exit Point:    -35.3620, 149.1670  (transit at 15m altitude)

MISSION COMMAND SEQUENCE:
  1. TAKEOFF to 15 m
  2. NAV_WAYPOINT to Field Entry Point (15m alt)
  3. DO_CHANGE_SPEED: set ground speed to 3 m/s
  4. NAV_WAYPOINT: Spray Pass 1 Start (8m alt)
  5. NAV_WAYPOINT: Spray Pass 1 End (8m alt)
  6. NAV_WAYPOINT: Spray Pass 2 Start (8m alt)
  7. NAV_WAYPOINT: Spray Pass 2 End (8m alt)
  8. DO_CHANGE_SPEED: set ground speed to 8 m/s
  9. NAV_WAYPOINT to Field Exit Point (15m alt)
  10. RTL (Return to Launch)

NOTES:
- DO_CHANGE_SPEED command (MAV_CMD 178): param1=1 (ground speed), param2=speed in m/s, param3=-1 (no throttle change)
- All altitudes are relative to home (AltitudeMode=1, frame=3)
- Save completed mission to: /home/ga/Documents/QGC/spray_mission.plan

APPROVED BY: J. Henderson, Chief Agronomist
SPECDOC

chown ga:ga /home/ga/Documents/QGC/spray_spec.txt

# 3. Ensure a clean state by removing any pre-existing plan
rm -f /home/ga/Documents/QGC/spray_mission.plan

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

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

echo "=== crop_spray_speed_mission task setup complete ==="
echo "Spec doc: /home/ga/Documents/QGC/spray_spec.txt"
echo "Expected output: /home/ga/Documents/QGC/spray_mission.plan"