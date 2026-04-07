#!/bin/bash
set -euo pipefail
echo "=== Setting up corridor_canal_inspection task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the inspection brief document
cat > /home/ga/Documents/QGC/canal_inspection_brief.txt << 'REQDOC'
IRRIGATION CANAL THERMAL INSPECTION BRIEF
Project: Murrumbidgee Irrigation Area - Sector 4 Seepage Scan
Date: 2026-03-09
Prepared by: Water Infrastructure Manager

=== INSPECTION ROUTE ===
You must create a Corridor Scan following this canal segment.
Place vertices approximately along these coordinates:
  1. Intake:   -34.2870°N, 146.0350°E
  2. Seepage:  -34.2885°N, 146.0410°E
  3. Junction: -34.2900°N, 146.0475°E
  4. Outlet:   -34.2912°N, 146.0530°E

=== CORRIDOR SETTINGS ===
The canal is 40 m wide. To capture the banks and adjacent soil where
seepage manifests, the total Corridor Width must be set to 80 m.

=== CAMERA SYSTEM ===
Camera model:    FLIR Vue Pro R 640 (Thermal)
Sensor width:    10.88 mm
Sensor height:   8.70 mm
Image width:     640 pixels
Image height:    512 pixels
Focal length:    13 mm

=== FLIGHT PARAMETERS ===
Required Ground Sampling Distance (GSD): 8.0 cm/pixel (0.08 m/px)

Calculate required altitude using this formula:
Altitude = (GSD_m_per_px × Focal_Length_mm × Image_Width_px) / Sensor_Width_mm
Altitude = (0.08 × 13 × 640) / 10.88
Altitude = ~61.2 m AGL  <-- USE THIS VALUE IN QGC

Frontal (forward) overlap: 70%
Side (lateral) overlap:    60%

=== MISSION FILE REQUIREMENTS ===
- You MUST use the Corridor Scan pattern (Plan View > Pattern > Corridor Scan).
  Do NOT use a Survey or simple waypoints.
- Draw the corridor path along the coordinates provided.
- Set the camera specs, altitude, width, and overlaps.
- Save the completed plan to: /home/ga/Documents/QGC/canal_inspection.plan
REQDOC

chown ga:ga /home/ga/Documents/QGC/canal_inspection_brief.txt

# Remove any existing plan file
rm -f /home/ga/Documents/QGC/canal_inspection.plan

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

echo "=== corridor_canal_inspection task setup complete ==="
echo "Brief document: /home/ga/Documents/QGC/canal_inspection_brief.txt"
echo "Expected output: /home/ga/Documents/QGC/canal_inspection.plan"