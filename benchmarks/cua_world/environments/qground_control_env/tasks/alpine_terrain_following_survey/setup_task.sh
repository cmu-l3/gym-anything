#!/bin/bash
echo "=== Setting up alpine_terrain_following_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write project briefing document
cat > /home/ga/Documents/QGC/glacier_briefing.txt << 'REQDOC'
GLACIER RETREAT MONITORING - FLIGHT BRIEFING
Project: Aletsch Glacier Topographic Survey
Client: Swiss Alpine Research Institute
Date: 2026-03-10

=== SURVEY AREA ===
Location: Aletsch Glacier region, Switzerland
Center Coordinate: 46.4350° N, 8.0200° E
(Search these coordinates in QGC to center your map)

=== CRITICAL SAFETY REQUIREMENT: TERRAIN FOLLOWING ===
The terrain in this region has a massive elevation gradient.
Flying at a standard fixed Mean Sea Level (MSL) altitude will result in Controlled Flight Into Terrain (CFIT).
You MUST enable "Terrain Following" in the QGroundControl survey settings.
This ensures the drone maintains a constant Above Ground Level (AGL) altitude by following the mountain's slope.

=== FLIGHT PARAMETERS ===
- Mission Type: Survey (Plan View > Pattern > Survey)
- Terrain Following: ENABLED (Checkbox must be checked)
- Flight Altitude: 50 m
- Frontal Overlap: 80%
- Side Overlap: 80%

=== DELIVERABLE ===
Save the completed mission plan file to:
/home/ga/Documents/QGC/glacier_survey.plan

Ensure the file is saved in the standard QGC .plan (JSON) format.
REQDOC

chown ga:ga /home/ga/Documents/QGC/glacier_briefing.txt

# 3. Record task start time
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

echo "=== alpine_terrain_following_survey task setup complete ==="
echo "Briefing document: /home/ga/Documents/QGC/glacier_briefing.txt"
echo "Expected output: /home/ga/Documents/QGC/glacier_survey.plan"