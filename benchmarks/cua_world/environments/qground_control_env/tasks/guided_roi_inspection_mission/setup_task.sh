#!/bin/bash
echo "=== Setting up guided_roi_inspection_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Remove any pre-existing plan file
rm -f /home/ga/Documents/QGC/tower_inspection.plan

# 3. Create the inspection work order document
cat > /home/ga/Documents/QGC/inspection_workorder.txt << 'WORKORDER'
============================================================
        TOWER INSPECTION WORK ORDER #TI-2024-0847
============================================================

Client:        Regional Telecom Services Pty Ltd
Site ID:       RTS-ACT-0173
Site Name:     Canberra North Cell Tower
Date Issued:   2026-03-09

TOWER LOCATION
--------------
  Latitude:    -35.3600
  Longitude:   149.1680
  Tower Height: 45 meters AGL
  Structure:   Monopole with 3 antenna arrays

INSPECTION REQUIREMENTS
-----------------------
  Orbit Radius:     30 meters from tower center
  Orbit Altitude:   50 meters AGL (above tower top for safety)
  Number of Orbits: 2 complete rotations (720 degrees)
  Camera Target:    Tower midpoint (approx. 25m AGL)
                    Set ROI to tower base coordinates at 25m altitude

MISSION REQUIREMENTS
--------------------
  1. Takeoff from current location
  2. Set Region of Interest (ROI) to tower coordinates at 25m altitude
     so camera gimbal tracks the tower midpoint throughout the orbit
  3. Execute 2 full orbits at 30m radius, 50m altitude
  4. Return to Launch (RTL) after orbit completion

OUTPUT
------
  Save mission plan to:
    /home/ga/Documents/QGC/tower_inspection.plan

SAFETY NOTES
-------------
  - Maintain minimum 5m clearance above tower top (tower = 45m)
  - Orbit radius must be >= 20m to avoid rotor wash effects on antennas
  - Maximum orbit radius 40m to maintain useful image resolution

MAVLink COMMAND REFERENCE (for manual editing if needed)
---------------------------------------------------------
  DO_SET_ROI = command 201
    params: [0, 0, 0, 0, latitude, longitude, altitude]

  LOITER_TURNS = command 18
    params: [turns, 0, radius, 0, latitude, longitude, altitude]
    Positive radius = clockwise orbit

  NAV_TAKEOFF = command 22
  NAV_RETURN_TO_LAUNCH = command 20
============================================================
WORKORDER

chown ga:ga /home/ga/Documents/QGC/inspection_workorder.txt

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

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

echo "=== guided_roi_inspection_mission task setup complete ==="
echo "Work order: /home/ga/Documents/QGC/inspection_workorder.txt"
echo "Expected output: /home/ga/Documents/QGC/tower_inspection.plan"