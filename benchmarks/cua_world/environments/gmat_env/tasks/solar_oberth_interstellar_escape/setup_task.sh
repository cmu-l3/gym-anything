#!/bin/bash
set -euo pipefail

echo "=== Setting up solar_oberth_interstellar_escape task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/GMAT_output/oberth_maneuver.script
rm -f /home/ga/GMAT_output/oberth_results.txt
rm -f /home/ga/Desktop/interstellar_oberth_baseline.txt
mkdir -p /home/ga/GMAT_output
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create baseline document
cat > /home/ga/Desktop/interstellar_oberth_baseline.txt << 'EOF'
=== NASA Interstellar Probe - Solar Oberth Baseline ===
Document Revision: 1.2
Objective: Achieve a heliocentric hyperbolic excess velocity of ~38.7 km/s (C3 = 1500 km^2/s^2) to reach interstellar space rapidly.

INITIAL STATE (Post-Jupiter Reverse Gravity Assist)
Central Body:      Sun
Coordinate System: SunMJ2000Eq
Epoch:             01 Jan 2030 12:00:00.000 UTC
State Type:        Keplerian
SMA:               374000000 km
ECC:               0.98
INC:               0.0 deg
RAAN:              0.0 deg
AOP:               0.0 deg
TA:                180.0 deg (starting at aphelion)

MANEUVER SEQUENCE
1. Propagate the spacecraft from its initial state to Sun periapsis (r ~ 0.05 AU).
2. At exact periapsis, execute a prograde impulsive burn (Velocity direction in Local VNB).
3. Use a DifferentialCorrector to determine the required burn magnitude to achieve a target C3 Energy of exactly 1500.0 km^2/s^2 with respect to the Sun.

REPORTING REQUIREMENTS
Write the final results to ~/GMAT_output/oberth_results.txt containing exactly these lines (with your computed values):
DeltaV_kms: <value>
Perihelion_Velocity_kms: <value>  (Note: the inertial velocity IMMEDIATELY AFTER the burn)
Final_C3_km2s2: <value>
EOF

chown ga:ga /home/ga/Desktop/interstellar_oberth_baseline.txt

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