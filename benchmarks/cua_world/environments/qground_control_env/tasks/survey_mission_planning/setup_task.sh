#!/bin/bash
echo "=== Setting up survey_mission_planning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write survey requirements document (the agent must read this to get specs)
cat > /home/ga/Documents/QGC/survey_requirements.txt << 'REQDOC'
PHOTOGRAMMETRIC SURVEY MISSION REQUIREMENTS
Project: Precision Agriculture Mapping – Wheat Field (Block 7-C)
Client: Zurich Agri Analytics GmbH
Date: 2026-03-09
Prepared by: Field Operations Manager

=== SURVEY AREA ===
Location: Near Zurich, Switzerland
Center coordinate: 47.3977°N, 8.5456°E
Approximate field area: 0.5 km² (rectangular, approx. 800m × 625m)

=== DELIVERABLE SPECIFICATIONS ===
Product: Orthomosaic + Digital Surface Model (DSM)
Required Ground Sampling Distance (GSD): 4.0 cm/pixel
(This is the contracted resolution — do not plan above or below this GSD)

=== CAMERA SYSTEM ===
Camera model:    Sony α5100
Sensor width:    23.5 mm
Sensor height:   15.6 mm
Image width:     6000 pixels
Image height:    4000 pixels
Focal length:    16 mm (fixed prime lens, no zoom)

=== REQUIRED FLIGHT PARAMETERS ===
To achieve 4.0 cm/pixel GSD with the above camera:

  Flight altitude = (GSD × focal_length × image_width) / sensor_width
  Flight altitude = (0.04 m/px × 16 mm × 6000 px) / 23.5 mm
  Flight altitude = 163.4 m AGL  ← USE THIS VALUE

Frontal (forward) overlap: 75%
Side (lateral) overlap:    65%

=== MISSION FILE REQUIREMENTS ===
- Use QGroundControl Survey pattern (Plan View > Pattern > Survey)
- Set camera to Sony α5100 or manually enter the specs above
- Target altitude: 163.4 m (acceptable range: 155–172 m)
- Save completed plan to: /home/ga/Documents/QGC/field_survey.plan
- File must be in QGC .plan format (JSON)

=== NOTES ===
- SITL home position is at the field center (47.3977°N, 8.5456°E)
- Survey polygon should cover at least 100m × 100m around home
- The photogrammetry pipeline requires BOTH overlap values — do not skip
REQDOC

chown ga:ga /home/ga/Documents/QGC/survey_requirements.txt

# 3. Record task start time for mtime checks
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

echo "=== survey_mission_planning task setup complete ==="
echo "Requirements document: /home/ga/Documents/QGC/survey_requirements.txt"
echo "Expected output: /home/ga/Documents/QGC/field_survey.plan"
