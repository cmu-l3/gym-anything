#!/bin/bash
set -euo pipefail

echo "=== Setting up tundra_orbit_longitude_targeting task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/borealis_mission_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create spec document (Real-world style constraint sheet)
cat > /home/ga/Desktop/borealis_mission_spec.txt << 'SPECEOF'
======================================================
BOREALIS CONSTELLATION - TUNDRA ORBIT SPECIFICATION
======================================================
Target Region: North America (Canada / Arctic)

ORBITAL ELEMENTS (EarthMJ2000Eq):
  Epoch:      01 Mar 2026 12:00:00.000 UTC
  SMA:        42164.17 km
  ECC:        0.28
  INC:        63.4 deg  (Critical inclination)
  AOP:        270.0 deg (Apogee in Northern Hemisphere)
  TA:         0.0 deg   (Start at Perigee)
  RAAN:       [TO BE DETERMINED]

TARGETING REQUIREMENT:
  The operational requirement is that the spacecraft's Apogee
  must occur exactly over longitude 105.0° West (i.e., -105.0°).

DYNAMICS MODEL:
  Primary Body: Earth
  Gravity: J2 only (Degree 2, Order 0)
  Point Masses: None required for preliminary targeting
  Atmosphere/SRP: None

TASK INSTRUCTIONS:
  1. Create a GMAT script to determine the required initial RAAN.
  2. Use a DifferentialCorrector to Vary RAAN and Achieve Spacecraft.Earth.Longitude = -105.0 at Apoapsis.
  3. Propagate to Apoapsis.
  4. Write the results to a ReportFile located at:
     /home/ga/GMAT_output/apogee_target_report.txt
  5. The report MUST contain at least these variables:
     - Spacecraft.A1ModJulian (or Epoch)
     - Spacecraft.EarthMJ2000Eq.RAAN
     - Spacecraft.Earth.Latitude
     - Spacecraft.Earth.Longitude
     - Spacecraft.Earth.Altitude
  6. Save your GMAT script to /home/ga/GMAT_output/borealis_tundra.script
======================================================
SPECEOF

chown ga:ga /home/ga/Desktop/borealis_mission_spec.txt

# Launch GMAT
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