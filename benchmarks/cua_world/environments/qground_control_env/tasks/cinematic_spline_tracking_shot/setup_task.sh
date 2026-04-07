#!/bin/bash
echo "=== Setting up cinematic_spline_tracking_shot task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write director's shot list
cat > /home/ga/Documents/QGC/director_shot_list.txt << 'EOF'
DIRECTOR'S AERIAL SHOT LIST
Scene: River Rowing Practice Tracking
Location: Molonglo River, Canberra
Date: 2026-03-09

REQUIREMENTS FOR FLIGHT PLAN:
- The drone must fly a completely smooth trajectory to avoid jerking the camera.
- You MUST use "Spline Waypoint" (NAV_SPLINE_WAYPOINT) instead of standard waypoints for all 5 river coordinates.

INITIALIZATION COMMANDS (Before the path):
1. Takeoff
2. Set Speed (DO_CHANGE_SPEED): 4 m/s (to match the rowers)
3. Set Gimbal Orientation (DO_MOUNT_CONTROL): Pitch = -15 degrees (to keep them in frame)

SPLINE WAYPOINT COORDINATES:
Point 1: -35.2986, 149.1115
Point 2: -35.2988, 149.1130
Point 3: -35.2983, 149.1145
Point 4: -35.2975, 149.1160
Point 5: -35.2965, 149.1175

ALTITUDE:
All Spline Waypoints must be exactly 25 meters.

TERMINATION:
End the mission with a Return to Launch (RTL) command.

DELIVERABLE:
Save the plan file to: /home/ga/Documents/QGC/river_tracking_shot.plan
EOF

chown ga:ga /home/ga/Documents/QGC/director_shot_list.txt

# 3. Record task start time for anti-gaming (mtime checks)
date +%s > /tmp/task_start_time

# 4. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 5. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== cinematic_spline_tracking_shot task setup complete ==="
echo "Director's Shot List: /home/ga/Documents/QGC/director_shot_list.txt"
echo "Expected Output: /home/ga/Documents/QGC/river_tracking_shot.plan"