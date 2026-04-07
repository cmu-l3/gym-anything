#!/bin/bash
set -euo pipefail

echo "=== Setting up mars_sso_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean workspace
rm -f /home/ga/Desktop/mars_sso_spec.txt
rm -f /home/ga/Documents/missions/mars_sso.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Write the spec to desktop
cat > /home/ga/Desktop/mars_sso_spec.txt << 'SPECEOF'
========================================
 ARES MAPPER - MARS SCIENCE ORBITER
 ORBIT DESIGN SPECIFICATION
========================================

MISSION OBJECTIVE:
Maintain a consistent 400 km circular science orbit around Mars with
sun-synchronous nodal precession to provide consistent surface lighting.

ORBITAL REQUIREMENTS:
  Central Body:       Mars
  Altitude:           400.0 km (circular)
  Orbit Type:         Sun-synchronous
  Inclination:        To be calculated/targeted by analyst
  RAAN:               0.0 deg (for reference)
  Epoch:              01 Jan 2030 12:00:00.000 UTCG

  *Note: Orbital elements must be defined in a Mars-centered
   coordinate system aligned with the Mars equator.*

SPACECRAFT PROPERTIES:
  Dry Mass:           1500 kg
  Drag Area:          15.0 m^2
  Cd:                 2.2

ANALYSIS REQUIREMENTS:
  Propagator:         Mars-centered
  Gravity Model:      Mars50c (Degree/Order >= 2)
  Duration:           60 Earth days

REFERENCE CONSTANTS (Mars):
  Radius (R):         3396.19 km
  Grav. Param (mu):   42828.3 km^3/s^2
  J2:                 0.00196045
  Mars Year:          686.973 Earth days
SPECEOF

chown ga:ga /home/ga/Desktop/mars_sso_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/mars_sso_spec.txt ==="