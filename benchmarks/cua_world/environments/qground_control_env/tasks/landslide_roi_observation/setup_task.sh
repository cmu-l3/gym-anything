#!/bin/bash
echo "=== Setting up landslide_roi_observation task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write operations brief (agent must read this to get coordinates and plan specs)
cat > /home/ga/Documents/QGC/recon_brief.txt << 'OPDOC'
================================================================
GEOHAZARD RECONNAISSANCE - UAV FLIGHT OPERATIONS BRIEF
================================================================
Date: 2026-03-10
Site: Brienz Slope Instability (Canton Bern, Switzerland)
Mission Type: Oblique video documentation flight

OBJECTIVE:
Capture continuous gimbal-tracked video of the main scarp from
five observation positions arranged in an arc. The camera must 
continuously point at the landslide center throughout the observation 
arc using a Region of Interest (ROI) command.

LANDSLIDE CENTER (ROI TARGET):
  Latitude:   47.3990
  Longitude:  8.5475
  (Set ROI at ground level, altitude 0 m)

FLIGHT ALTITUDE: 80 m AGL (all waypoints and loiter points)

MISSION WAYPOINTS (fly in order):
  WP-A  Approach     47.3995°N  8.5450°E   80 m  (standard waypoint)
  WP-B  Obs North    47.3998°N  8.5475°E   80 m  (LOITER 2 TURNS)
  WP-C  Transit E    47.3993°N  8.5498°E   80 m  (standard waypoint)
  WP-D  Obs SE       47.3983°N  8.5498°E   80 m  (LOITER 2 TURNS)
  WP-E  Exit South   47.3978°N  8.5480°E   80 m  (standard waypoint)

COMMANDS SEQUENCE:
  1. Takeoff to 80 m
  2. Fly to WP-A (approach)
  3. SET ROI to landslide center coordinates
  4. Fly to WP-B and LOITER 2 TURNS (camera tracks ROI)
  5. Fly to WP-C (transit)
  6. Fly to WP-D and LOITER 2 TURNS (camera tracks ROI)
  7. Fly to WP-E (exit)
  8. RTL (Return to Launch)

NOTES:
- Use QGroundControl's Plan View.
- The ROI command must be placed BEFORE the first loiter point so the camera begins tracking immediately.
- Both LOITER TURNS commands require exactly 2 orbits.
- RTL is mandatory as the final command.
- Save mission as: /home/ga/Documents/QGC/landslide_recon.plan

Approved by: Dr. M. Keller, Chief Geologist
================================================================
OPDOC

chown ga:ga /home/ga/Documents/QGC/recon_brief.txt

# 3. Remove any pre-existing plan file
rm -f /home/ga/Documents/QGC/landslide_recon.plan

# 4. Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time

# 5. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize QGC window
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== landslide_roi_observation task setup complete ==="
echo "Operations brief: /home/ga/Documents/QGC/recon_brief.txt"
echo "Expected output: /home/ga/Documents/QGC/landslide_recon.plan"