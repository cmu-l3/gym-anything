#!/bin/bash
set -euo pipefail

echo "=== Setting up upper_stage_gto_finite_burn task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/upper_stage_specs.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
cat > /home/ga/Desktop/upper_stage_specs.txt << 'SPECEOF'
================================================================
UPPER STAGE GTO INJECTION — FINITE BURN SPECIFICATION
Mission: CommSat-Alpha
Document: LV-FDO-2025-04
================================================================

1. PARKING ORBIT (Initial State)
   Coordinate System: EarthMJ2000Eq
   Epoch: 10 Jun 2025 12:00:00.000 UTCG
   Semi-Major Axis: 6628.14 km (approx 250 km altitude)
   Eccentricity: 0.0
   Inclination: 28.5 deg
   RAAN: 0.0 deg
   Argument of Perigee: 0.0 deg
   True Anomaly: 0.0 deg

2. MASS PROPERTIES
   Dry Mass: 2500.0 kg (Upper stage dry mass + payload)
   Initial Fuel Mass: 15000.0 kg

3. PROPULSION SYSTEM (Main Engine)
   Engine Thrust: 110000.0 N
   Specific Impulse (Isp): 450.0 s
   Gravity Constant: 9.80665 m/s^2 (GMAT default)
   Thrust Direction: Prograde (Aligned with velocity vector, local VNB)

4. MANEUVER PLAN
   - Propagate in the LEO parking orbit until True Anomaly = 180.0 deg (Descending Node).
   - Ignite main engine for a continuous finite burn.
   - Continue the burn until the spacecraft's Apoapsis radius (Sat.Earth.Apoapsis) reaches exactly 42164.14 km.
   - Terminate the burn immediately.

5. OUTPUT REQUIREMENTS
   Generate a text file at ~/GMAT_output/gto_injection_report.txt containing exactly:
   burn_duration_seconds: <your calculated value>
   final_apoapsis_km: <achieved apoapsis radius>
   remaining_fuel_kg: <fuel mass remaining in tank after burn>
SPECEOF

chown ga:ga /home/ga/Desktop/upper_stage_specs.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/upper_stage_specs.txt ==="