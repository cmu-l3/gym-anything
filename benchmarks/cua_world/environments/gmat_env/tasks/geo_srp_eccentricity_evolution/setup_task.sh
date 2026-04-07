#!/bin/bash
set -euo pipefail

echo "=== Setting up geo_srp_eccentricity_evolution task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/geo_srp_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
cat > /home/ga/Desktop/geo_srp_spec.txt << 'SPECEOF'
===========================================
 SATCOM-9 Geostationary Communications Satellite
 GEO Stationkeeping Analysis — SRP Characterization
===========================================

Satellite: SATCOM-9
Operator: Pacific Telecom Ltd
GEO Slot: 135.0 deg East longitude

ORBITAL ELEMENTS (Epoch: 01 Jan 2025 12:00:00.000 UTCG):
  Coordinate System: EarthMJ2000Eq
  SMA:    42164.17 km
  ECC:    0.0002
  INC:    0.05 deg
  RAAN:   0.0 deg
  AOP:    0.0 deg
  TA:     225.0 deg  (places satellite near 135E longitude)

PHYSICAL PROPERTIES:
  Dry Mass:           2200 kg
  SRP Area:           45.0 m^2  (large solar panel span)
  SRP Coefficient Cr: 1.2  (specular + diffuse mix)
  Drag Area:          25.0 m^2
  Drag Coefficient:   2.2

FORCE MODEL REQUIREMENTS:
  Gravity:       Earth 12x12 (JGM-2 or JGM-3)
  Third Body:    Sun, Moon
  SRP:           Enabled (Spherical model)
  Drag:          Disabled (negligible at GEO)

PROPAGATION:
  Duration: 365 days
  Output Step: 1.0 days (or finer)
  Propagator: RungeKutta89 or PrinceDormand78

ANALYSIS DELIVERABLES:
  1. Time history of eccentricity components
  2. Maximum eccentricity reached
  3. Eccentricity circle radius estimate
  4. Confirmation that oscillation period ~ 1 year
===========================================
SPECEOF

chown ga:ga /home/ga/Desktop/geo_srp_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/geo_srp_spec.txt ==="