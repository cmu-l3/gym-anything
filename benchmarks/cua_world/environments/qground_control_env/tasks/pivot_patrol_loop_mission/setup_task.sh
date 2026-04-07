#!/bin/bash
echo "=== Setting up pivot_patrol_loop_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the patrol requirements document
cat > /home/ga/Documents/QGC/patrol_requirements.txt << 'REQDOC'
IRRIGATION PIVOT PATROL REQUIREMENTS
Location: Sector 4 Center Pivot
Date: 2026-03-09

=== MISSION OVERVIEW ===
The drone must fly to the irrigation pivot, patrol around its perimeter 3 times
at a slow inspection speed, and then return to launch. 

=== WAYPOINTS (PATROL CORNERS) ===
Create a rectangular path around the pivot using these 4 coordinate corners:
  WP1 (NW): -35.3625, 149.1645
  WP2 (NE): -35.3625, 149.1665
  WP3 (SE): -35.3645, 149.1665
  WP4 (SW): -35.3645, 149.1645

All patrol waypoints must be at an altitude of 40 meters.

=== SPEED CONTROL ===
- Transit speed: 8 m/s (Set this before the drone flies to the first waypoint)
- Inspection speed: 3 m/s (Set this just before the patrol loop begins, e.g., right before or at WP1)
- Return speed: 8 m/s (Set this after the patrol loops are finished, before returning home)
Use the DO_CHANGE_SPEED command to set speeds.

=== REPEATING THE LOOP ===
After reaching WP4, the drone must repeat the rectangular patrol.
Use a DO_JUMP command (found in the command list under conditional/logic).
- Jump to: The sequence number of WP1
- Repeat count: 3
This will cause the drone to circle the pivot 3 additional times.

=== END OF MISSION ===
Add an RTL (Return To Launch) command at the very end of the mission so the vehicle returns home.

=== OUTPUT FILE ===
Save the completed mission plan to:
/home/ga/Documents/QGC/pivot_patrol.plan
REQDOC

chown ga:ga /home/ga/Documents/QGC/patrol_requirements.txt

# 3. Clean up any existing plan files
rm -f /home/ga/Documents/QGC/pivot_patrol.plan

# 4. Record task start time for anti-gaming (mtime checks)
date +%s > /tmp/task_start_time

# 5. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize QGC, dismiss dialogs
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== pivot_patrol_loop_mission task setup complete ==="
echo "Requirements document: /home/ga/Documents/QGC/patrol_requirements.txt"
echo "Expected output: /home/ga/Documents/QGC/pivot_patrol.plan"