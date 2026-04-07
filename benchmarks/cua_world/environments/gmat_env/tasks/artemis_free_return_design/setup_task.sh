#!/bin/bash
set -euo pipefail

echo "=== Setting up artemis_free_return_design task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

rm -f /home/ga/Desktop/artemis_tli_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

date +%s > /tmp/task_start_time.txt

cat > /home/ga/Desktop/artemis_tli_spec.txt << 'EOF'
================================================================
ARTEMIS II CISLUNAR TRAJECTORY DESIGN SPECIFICATION
Document: ART-TRAJ-2025-04
Phase: Trans-Lunar Injection (TLI) Free-Return Targeting
================================================================

1. INITIAL PARKING ORBIT (LEO)
   Spacecraft:          Orion
   CoordinateSystem:    EarthMJ2000Eq
   Epoch:               01 Dec 2025 12:00:00.000 UTCG
   SMA:                 6771.14 km  (400 km circular)
   ECC:                 0.0
   INC:                 28.5 deg
   RAAN:                0.0 deg
   AOP:                 0.0 deg
   TA (Initial Guess):  150.0 deg

2. FORCE MODEL REQUIREMENTS
   Central Body:        Earth
   Point Masses:        Earth, Luna
   Drag / SRP:          None (Vacuum trajectory simulation)

3. TARGETING CONSTRAINTS & GUESSES
   To achieve a free-return, you must vary the burn magnitude AND the 
   location of the burn (by varying the initial True Anomaly in the parking orbit).

   Variables:
     - Vary Orion.TA (Guess = 150.0, Lower = 0.0, Upper = 360.0)
     - Vary TLI.Element1 [Prograde dV] (Guess = 3.15 km/s, Lower = 3.0, Upper = 3.3)

   Sequence & Constraints:
     - Apply TLI burn
     - Propagate to Lunar Periapsis (Luna.Periapsis)
     - Achieve Lunar Flyby Radius (Orion.Luna.RMAG) = 4000 km (tolerance 1.0)
     - Propagate to Earth Periapsis (Earth.Periapsis)
     - Achieve Earth Reentry Radius (Orion.Earth.RMAG) = 6411.14 km (tolerance 1.0)

4. DELIVERABLES
   Save your GMAT script to ~/GMAT_output/artemis_free_return.script
   Write the converged TA, TLI Delta-V, Achieved Luna RMAG, and Achieved Earth RMAG 
   to ~/GMAT_output/free_return_results.txt.
EOF
chown ga:ga /home/ga/Desktop/artemis_tli_spec.txt

echo "Launching GMAT..."
launch_gmat ""

WID=$(wait_for_gmat_window 60)
if [ -n "$WID" ]; then
    sleep 5
    dismiss_gmat_dialogs
    focus_gmat_window
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start"
    exit 1
fi

echo "=== Setup complete ==="