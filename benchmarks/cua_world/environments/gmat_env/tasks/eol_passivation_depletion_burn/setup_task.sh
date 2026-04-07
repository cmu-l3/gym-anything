#!/bin/bash
set -euo pipefail

echo "=== Setting up eol_passivation_depletion_burn task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/passivation_specs.txt
rm -f /home/ga/Documents/missions/passivation.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the specification document
cat > /home/ga/Desktop/passivation_specs.txt << 'SPECEOF'
======================================================
PASSIVATION MANEUVER SPECIFICATION
Document: EOL-PASS-2026
======================================================

1. SPACECRAFT INITIAL STATE
   Name: PassivationSat
   Epoch: 01 Jun 2026 12:00:00.000 UTC
   Coordinate System: EarthMJ2000Eq
   Orbit: 800 km circular
   SMA: 7171.14 km
   ECC: 0.0
   INC: 98.5 deg
   RAAN: 45.0 deg
   AOP: 0.0 deg
   TA: 0.0 deg

2. MASS PROPERTIES
   Dry Mass: 475.0 kg
   Propellant Mass: 25.0 kg (Hydrazine)

3. PROPULSION HARDWARE
   Tank Name: DepletionTank
   Thruster Name: DepletionThruster
   Thrust: 22.0 N
   Specific Impulse (Isp): 225.0 s
   
4. MANEUVER PROFILE
   Type: Continuous Finite Burn
   Direction: Purely Retrograde (Anti-Velocity)
   Termination: Fuel depletion (Tank FuelMass = 0 kg)

5. OUTPUT REQUIREMENTS
   Report to: ~/GMAT_output/passivation_report.txt
   Required fields (format: Key: Value):
   - initial_mass_kg
   - final_mass_kg
   - final_periapsis_alt_km
   - burn_duration_sec
======================================================
SPECEOF

chown ga:ga /home/ga/Desktop/passivation_specs.txt

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