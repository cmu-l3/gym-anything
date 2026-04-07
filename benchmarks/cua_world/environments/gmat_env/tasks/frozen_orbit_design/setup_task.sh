#!/bin/bash
set -euo pipefail

echo "=== Setting up frozen_orbit_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/eo_mission_requirements.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the mission requirements document
cat > /home/ga/Desktop/eo_mission_requirements.txt << 'DOCEOF'
=== TERRA-VISION-3 MISSION REQUIREMENTS ===
Document: TV3-MRD-2025-003
Classification: UNCLASSIFIED

MISSION OVERVIEW
Terra-Vision-3 is a high-resolution multispectral Earth observation
satellite designed for 0.5m GSD imaging. Consistent ground sample
distance requires stable altitude over target regions.

ORBIT REQUIREMENTS
  Nominal Altitude:   700 km (circular)
  Orbit Type:         Sun-synchronous
  LTAN:               10:30 AM descending node
  Orbit Stability:    Altitude variation < 10 km over 60 days
                      (frozen orbit design mandatory)

SPACECRAFT PARAMETERS
  Dry Mass:           1200 kg
  Drag Cross-Section: 6.5 m^2
  Drag Coefficient:   2.2
  SRP Cross-Section:  12.0 m^2
  SRP Coefficient:    1.3

EPOCH
  Reference Epoch:    01 Mar 2025 12:00:00.000 UTCG

INITIAL ORBITAL ELEMENTS (Keplerian, Earth MJ2000Eq)
  SMA:     7078.14 km
  ECC:     [TO BE DETERMINED - FROZEN ORBIT CONDITION]
  INC:     98.19 deg (sun-synchronous for 700 km)
  RAAN:    150.0 deg
  AOP:     [TO BE DETERMINED - FROZEN ORBIT CONDITION]
  TA:      0.0 deg

FORCE MODEL REQUIREMENTS
  Earth Gravity:      Minimum 10x10 spherical harmonics
  Atmospheric Drag:   JacchiaRoberts or MSISE model
  Solar Radiation:    Spherical SRP model
  Third Body:         Sun and Moon point masses

NOTES
  The frozen orbit eccentricity must be computed from the J2/J3
  zonal harmonic balance condition. The argument of perigee for
  a frozen orbit in the northern hemisphere is 90 degrees.

  Reference: e_frozen = -(J3 * Re) / (2 * J2 * a) * sin(i)
  where J2 = 1.08263e-3, J3 = -2.5326e-6, Re = 6378.137 km
DOCEOF

chown ga:ga /home/ga/Desktop/eo_mission_requirements.txt

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

echo "=== Task Setup Complete: Requirements doc at ~/Desktop/eo_mission_requirements.txt ==="