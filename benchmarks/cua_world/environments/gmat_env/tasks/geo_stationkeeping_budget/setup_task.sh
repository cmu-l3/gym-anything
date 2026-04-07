#!/bin/bash
set -euo pipefail

echo "=== Setting up geo_stationkeeping_budget task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/geosat_assignment.txt
rm -f /home/ga/Documents/missions/stationkeeping.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Write specification document
cat > /home/ga/Desktop/geosat_assignment.txt << 'SPECEOF'
=== AsiaCom-3 GEO Stationkeeping Assignment ===
Operator: AsiaCom Satellite Services
Satellite: AsiaCom-3
ITU Filing: AP30B-2024-0731

ASSIGNED ORBITAL SLOT
  Longitude: 120.0 deg West (240.0 deg East)
  Deadband:  +/- 0.05 deg longitude, +/- 0.05 deg latitude

SPACECRAFT PARAMETERS
  Dry Mass:          3200 kg
  SRP Area:          42.0 m^2 (deployed solar array cross-section)
  Reflectivity Cr:   1.3
  Note: No atmospheric drag at GEO altitude

INITIAL ORBITAL STATE (EarthMJ2000Eq)
  Epoch:    01 Jul 2025 12:00:00.000 UTCG
  SMA:      42164.17 km
  ECC:      0.0002
  INC:      0.05 deg
  RAAN:     270.0 deg
  AOP:      0.0 deg
  TA:       90.0 deg

FORCE MODEL REQUIREMENTS
  Earth gravity:  JGM-3 or EGM-96, minimum order 12x12
  Third bodies:   Sun, Moon (REQUIRED for N-S analysis)
  SRP:            ON (significant for 42 m^2 array area)
  Drag:           OFF (not applicable at GEO)

ANALYSIS REQUIREMENTS
  1. Propagate orbit for exactly 30 days under full perturbation environment
  2. Record time-series of: inclination (deg), longitude (deg), SMA (km), eccentricity
  3. Measure inclination growth rate (deg/year) - extrapolate from 30-day trend
  4. Measure longitude drift rate (deg/year) - extrapolate from 30-day trend
  5. Determine longitude drift direction (Eastward or Westward)
  6. Compute annual N-S stationkeeping delta-V (m/s/yr)
     Formula: DV_NS = 2 * V_GEO * sin(delta_INC_annual / 2)
     where V_GEO = 3074.7 m/s (approx circular velocity at GEO)
  7. Compute annual E-W stationkeeping delta-V (m/s/yr)
     Formula: DV_EW = (2*pi*a / P) * sin(delta_LON_annual / 2) * (1/number_of_burns)
     Typical: 1-5 m/s/yr depending on slot longitude
  8. Report total annual delta-V budget
SPECEOF

chown ga:ga /home/ga/Desktop/geosat_assignment.txt

# 4. Launch GMAT to establish the baseline working environment
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
    # We don't exit 1 to avoid instantly failing the task for a display glitch
fi

echo "=== Task Setup Complete: Spec document at ~/Desktop/geosat_assignment.txt ==="