#!/bin/bash
set -euo pipefail

echo "=== Setting up agile_eo_target_accessibility task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/eo_targets.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create requirements document
cat > /home/ga/Desktop/eo_targets.txt << 'DOCEOF'
======================================================
Agile EO Accessibility Study
======================================================

SPACECRAFT PARAMETERS:
  Name: AgileEO
  Altitude: 500 km (Circular)
  Inclination: 97.4 deg (Sun-Synchronous)
  RAAN: 45.0 deg
  AOP: 0.0 deg
  TA: 0.0 deg
  Epoch: 01 Jan 2025 12:00:00.000 UTC
  Coordinate System: EarthMJ2000Eq

SENSOR CONSTRAINTS:
  Sensor: High-Res Optical Imager
  Field of Regard: Maximum 30 degrees off-nadir
  Constraint: Any image taken at an angle > 30 degrees off-nadir is too distorted.
  
SIMULATION:
  Duration: Exactly 3 Days (72 hours)

TARGETS:
  1. Washington DC
     Latitude:  38.9072 N
     Longitude: 282.9631 E  (77.0369 W)
     
  2. Beijing
     Latitude:  39.9042 N
     Longitude: 116.4074 E
     
  3. Moscow
     Latitude:  55.7558 N
     Longitude: 37.6173 E

YOUR TASK:
Determine the total number of valid imaging passes for each target over the 3-day window.
You must mathematically convert the 30-degree off-nadir constraint into a ground-centric constraint (Minimum Elevation Angle) or apply it using a ConicalFOV sensor model. 

Save your GMAT script to ~/GMAT_output/agile_targeting.script
Write a summary file to ~/GMAT_output/accessibility_summary.txt containing the total valid pass counts for all three cities.
DOCEOF

chown ga:ga /home/ga/Desktop/eo_targets.txt

# 4. Launch GMAT
echo "Launching GMAT..."
launch_gmat ""

echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 60)

if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5
    dismiss_gmat_dialogs
    focus_gmat_window
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete ==="