#!/bin/bash
set -euo pipefail

echo "=== Setting up mars_aerobraking_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/aerobraking_spec.txt
rm -f /home/ga/Documents/missions/mars_aerobraking.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the specification document
cat > /home/ga/Desktop/aerobraking_spec.txt << 'SPECEOF'
=======================================================
MARS EXPLORER - AEROBRAKING CAMPAIGN SPECIFICATION
=======================================================

CENTRAL BODY PARAMETERS:
  Body: Mars
  Gravitational Parameter (mu): 42828.31 km^3/s^2
  Equatorial Radius: 3396.19 km

INITIAL ORBITAL STATE (Keplerian, MarsMJ2000Eq):
  Epoch: 10 Sep 2026 00:00:00.000 UTC
  SMA: 13458.69 km
  ECC: 0.738363
  INC: 89.0 deg
  RAAN: 45.0 deg
  AOP: 270.0 deg
  TA: 0.0 deg
  
  (Note: This corresponds to an initial Apoapsis Radius of ~23396.19 km 
   and a Periapsis Radius of ~3521.19 km)

SPACECRAFT PROPERTIES:
  Dry Mass: 1200.0 kg
  Drag Area: 35.0 m^2
  Coefficient of Drag (Cd): 2.2

PROPAGATION REQUIREMENTS:
  Duration: 60 Days
  Gravity: Point Mass ONLY (Degree=0, Order=0)
  Atmosphere: Mars Exponential

DELTA-V SAVINGS CALCULATION:
Compute the delta-V required to propulsively lower the apoapsis from its 
INITIAL value to its FINAL simulated value, assuming the burn occurs at 
the FINAL periapsis radius. 

  a_initial = (3521.19 + 23396.19) / 2 = 13458.69
  a_final = (R_periapsis_final + R_apoapsis_final) / 2

  V1 = sqrt( mu * (2/R_periapsis_final - 1/a_initial) )
  V2 = sqrt( mu * (2/R_periapsis_final - 1/a_final) )
  
  DeltaV_saved_mps = (V1 - V2) * 1000   [Convert km/s to m/s]

OUTPUT FORMAT REQUIRED (exact keys):
Write to ~/GMAT_output/aerobraking_results.txt:
initial_apoapsis_radius_km: 23396.19
final_periapsis_radius_km: [your value]
final_apoapsis_radius_km: [your value]
deltav_saved_mps: [your calculated value]
SPECEOF

chown ga:ga /home/ga/Desktop/aerobraking_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/aerobraking_spec.txt ==="