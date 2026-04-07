#!/bin/bash
set -euo pipefail

echo "=== Setting up finite_burn_gravity_loss task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean previous artifacts and set up directories
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

rm -f /home/ga/Desktop/orbit_raise_specs.txt

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create the specification document on the Desktop
cat > /home/ga/Desktop/orbit_raise_specs.txt << 'SPECEOF'
========================================================
  ORBIT RAISE SPECIFICATION DOCUMENT
  ClearView-7 Communications Satellite
  Prepared by: Mission Design Group
  Date: 15 Dec 2024
========================================================

SPACECRAFT PARAMETERS
  Name:              ClearView7
  Dry Mass:          500 kg
  Fuel Mass:         80 kg (MMH/NTO bipropellant)
  Drag Area:         3.5 m^2
  Cd:                2.2
  SRP Area:          3.5 m^2
  Cr:                1.8

PROPULSION SYSTEM
  Engine:            AKM-400 (biprop apogee motor)
  Thrust:            400 N (vacuum)
  Specific Impulse:  316 s
  Number of Engines: 1

INJECTION ORBIT (post-separation from launch vehicle)
  Epoch:             01 Jan 2025 12:00:00.000 UTC
  Semi-Major Axis:   6771.0 km   (400 km altitude, circular)
  Eccentricity:      0.0001
  Inclination:       28.5 deg
  RAAN:              0.0 deg
  AOP:               0.0 deg
  True Anomaly:      0.0 deg
  Coord System:      EarthMJ2000Eq

TARGET OPERATIONAL ORBIT
  Semi-Major Axis:   7171.0 km   (800 km altitude, circular)
  Eccentricity:      < 0.005
  Inclination:       28.5 deg  (no plane change required)

ANALYSIS REQUIREMENTS
  The propulsion team requires a comparison of ideal vs.
  realistic delta-V for fuel budget verification:

  1. Compute ideal (impulsive) two-burn Hohmann transfer
     delta-V from 400 km to 800 km circular.

  2. Compute finite-burn transfer delta-V using the AKM-400
     thruster specifications above. The finite burn must
     model the actual thrust duration and resulting gravity
     losses.

  3. Quantify the gravity loss penalty:
       gravity_loss_m_s = finite_total_dv_m_s - impulsive_total_dv_m_s

  4. Save GMAT script to:
       ~/GMAT_output/gravity_loss_mission.script

  5. Write results report to:
       ~/GMAT_output/gravity_loss_report.txt

  Report must include these fields (one per line, colon-separated):
     impulsive_dv1_m_s
     impulsive_dv2_m_s
     impulsive_total_dv_m_s
     impulsive_final_sma_km
     finite_dv1_eff_m_s
     finite_dv2_eff_m_s
     finite_total_dv_m_s
     finite_final_sma_km
     gravity_loss_m_s
     gravity_loss_percent
========================================================
SPECEOF

chown ga:ga /home/ga/Desktop/orbit_raise_specs.txt

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