#!/bin/bash
echo "=== Setting up thermal_wildlife_survey_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write survey requirements document (the agent must read this to get specs)
cat > /home/ga/Documents/QGC/wetland_survey_spec.txt << 'REQDOC'
THERMAL WILDLIFE SURVEY - OPERATIONAL BRIEF
Project: Night Waterfowl Count - Wetland Sector 4
Date: 2026-03-09

=== SENSOR LIMITATION WARNING ===
Payload: FLIR Boson 640 Thermal Camera (9Hz export-unrestricted model)
Because the sensor refresh rate is so low (9Hz), continuous flight while triggering 
photos will cause unacceptable motion smear. You MUST use "Hover and Capture" 
mechanics so the drone stops completely before each photo.

Additionally, to prevent pendulum swinging from bleeding into the photo line, 
you must set an extended turnaround distance outside the grid.

=== MISSION REQUIREMENTS ===
1. Use a standard Survey Pattern enclosing the area near the drone's home position.
2. Under Camera settings, select "Manual (no camera specs)" / Custom Camera.
3. Enter the exact sensor details below:
   - Sensor Width:  7.68 mm
   - Sensor Height: 6.14 mm
   - Image Width:   640 pixels
   - Image Height:  512 pixels
   - Focal Length:  14.0 mm
4. Set the Survey Altitude to exactly 35 meters.
5. Check the "Hover and Capture" (or "Stop to take photo") option to prevent motion blur.
6. Set "Turnaround Distance" to exactly 15.0 meters.
7. Overlaps: Frontal 80%, Side 70%.

Save the completed survey plan to: /home/ga/Documents/QGC/thermal_survey.plan
REQDOC

chown ga:ga /home/ga/Documents/QGC/wetland_survey_spec.txt

# 3. Record task start time for mtime checks (anti-gaming)
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

echo "=== thermal_wildlife_survey_mission task setup complete ==="
echo "Brief document: /home/ga/Documents/QGC/wetland_survey_spec.txt"
echo "Expected output: /home/ga/Documents/QGC/thermal_survey.plan"