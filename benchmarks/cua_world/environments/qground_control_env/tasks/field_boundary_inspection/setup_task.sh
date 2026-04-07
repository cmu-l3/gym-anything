#!/bin/bash
echo "=== Setting up field_boundary_inspection task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write operations brief for the agent to read
cat > /home/ga/Documents/QGC/ops_brief.txt << 'OPDOC'
═══════════════════════════════════════════════════════
  FIELD BOUNDARY INSPECTION — OPERATIONS BRIEF
  Mission Date: 2026-06-15
  Prepared by: Operations Manager, AgriCoop Zurich
═══════════════════════════════════════════════════════

FIELD LOCATION (WGS84):
  Northwest corner:  47.3985 N,  8.5435 E
  Northeast corner:  47.3985 N,  8.5475 E
  Southeast corner:  47.3965 N,  8.5475 E
  Southwest corner:  47.3965 N,  8.5435 E

MISSION PARAMETERS:
  Takeoff altitude:      30 m AGL
  Cruise altitude:       30 m AGL (all waypoints)
  Default speed:         5 m/s

INSPECTION POINTS:
  1. Northeast corner (pump station):
     - Loiter for 30 seconds for thermal sensor dwell
  2. Southwest corner (gate mechanism):
     - Loiter for 20 seconds for visual inspection

DETAILED INSPECTION SEGMENT:
  Along the southern edge (SE corner → SW corner):
  - Reduce speed to 3 m/s BEFORE reaching the SE corner
  - This enables high-resolution crack detection on the
    irrigation channel running along the southern boundary

MISSION SEQUENCE:
  Takeoff → NW → NE → Loiter(30s) → SE → SW → Loiter(20s) → RTL

  Insert DO_CHANGE_SPEED (3 m/s) before the SE corner waypoint.

SAVE LOCATION:
  /home/ga/Documents/QGC/boundary_inspection.plan

SAFETY:
  Ensure RTL is the final command in the mission.
═══════════════════════════════════════════════════════
OPDOC

chown ga:ga /home/ga/Documents/QGC/ops_brief.txt

# 3. Clean any existing output files
rm -f /home/ga/Documents/QGC/boundary_inspection.plan

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

echo "=== field_boundary_inspection task setup complete ==="
echo "Operations brief: /home/ga/Documents/QGC/ops_brief.txt"
echo "Expected output: /home/ga/Documents/QGC/boundary_inspection.plan"