#!/bin/bash
set -euo pipefail

echo "=== Setting up OTV Rideshare Mission Design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/rideshare_specs.txt
rm -f /home/ga/Documents/missions/otv_rideshare.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the rideshare specifications document
cat > /home/ga/Desktop/rideshare_specs.txt << 'SPECEOF'
=== ORBITAL TRANSFER VEHICLE (OTV) RIDESHARE SPECIFICATION ===
Reference: Transporter-10 Rideshare Manifest

1. INITIAL STATE (EarthMJ2000Eq)
   Epoch: 01 Jan 2026 12:00:00.000 UTC
   Altitude: 400 km (SMA = 6771.14 km, Earth Radius = 6371.14 km)
   Eccentricity: 0.0
   Inclination: 97.0 deg
   RAAN: 0.0 deg
   AOP: 0.0 deg
   TA: 0.0 deg

2. SPACECRAFT HARDWARE
   Initial Dry Mass: 600 kg (Includes SpaceTug + Payload A + Payload B)
   Propellant Tank Type: ChemicalTank
   Initial Fuel Mass: 400 kg
   Propulsion: ImpulsiveBurn objects using the configured tank
   Engine Isp: 285 s
   (Note: Use these specific values so fuel depletion is calculated correctly)

3. MISSION SEQUENCE
   Phase 1: Deliver Payload A
   - Target Orbit: 500 km circular (SMA = 6871.14 km, INC = 97.0 deg)
   - Deployment: Reduce Spacecraft DryMass by 150 kg immediately after circularization.

   Phase 2: Deliver Payload B
   - Target Orbit: 600 km circular (SMA = 6971.14 km) AND Inclination = 99.0 deg
   - Maneuver constraint: To save fuel, perform the 2.0 degree inclination 
     change simultaneously with the apogee circularization burn at 600 km.
   - Deployment: Reduce Spacecraft DryMass by 100 kg immediately after circularization.
SPECEOF

chown ga:ga /home/ga/Desktop/rideshare_specs.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/rideshare_specs.txt ==="