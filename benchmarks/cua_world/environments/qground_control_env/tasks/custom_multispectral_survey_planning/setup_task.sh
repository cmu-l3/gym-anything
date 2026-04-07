#!/bin/bash
echo "=== Setting up custom_multispectral_survey_planning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the camera specification document
cat > /home/ga/Documents/QGC/camera_specs.txt << 'SPECDOC'
HARDWARE SPECIFICATION & FLIGHT PROFILE
Payload: Univ. Prototype Multispectral Sensor (Rev B)
Date: 2026-03-10

=== SENSOR PHYSICS & OPTICS ===
This is a custom-built 1-inch type sensor. Because it is not in the QGC default database,
you MUST select "Custom Camera" in the survey settings and enter these values precisely.
If the dimensions are wrong, the flight line spacing will be calculated incorrectly.

Sensor Width:    13.2 mm
Sensor Height:   8.8 mm
Image Width:     5472 pixels
Image Height:    3648 pixels
Focal Length:    12.0 mm (Fixed prime lens)

=== FLIGHT PROFILE ===
To achieve the target Ground Sampling Distance (GSD) of ~2.4 cm/px and ensure
sufficient overlap for the photogrammetry pipeline:

Target Altitude:   120 m
Frontal Overlap:   80 %
Side Overlap:      75 %

=== MISSION REQUIREMENTS ===
1. Begin with a Takeoff command.
2. Draw the survey polygon over the large green field directly north of the SITL home point.
3. Configure the Custom Camera and overlaps as specified above.
4. End the mission with an RTL command.
5. Save exactly as: /home/ga/Documents/QGC/multispectral_survey.plan
SPECDOC

chown ga:ga /home/ga/Documents/QGC/camera_specs.txt

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

echo "=== custom_multispectral_survey_planning task setup complete ==="
echo "Spec document: /home/ga/Documents/QGC/camera_specs.txt"
echo "Expected output: /home/ga/Documents/QGC/multispectral_survey.plan"