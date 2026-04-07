#!/bin/bash
set -euo pipefail

echo "=== Setting up asat_debris_dispersion task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

rm -f /home/ga/Desktop/kosmos_1408_asat_event.txt

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the ASAT Event document
cat > /home/ga/Desktop/kosmos_1408_asat_event.txt << 'DOCEOF'
=======================================================
  SPACE SITUATIONAL AWARENESS: FRAGMENTATION EVENT
  Target: Kosmos 1408 (NORAD ID 13552)
  Event Date: 15 Nov 2021
=======================================================

PARENT SATELLITE INITIAL STATE (At Impact Epoch)
Epoch: 15 Nov 2021 02:50:00.000 UTCG
Coordinate System: EarthMJ2000Eq
State Type: Keplerian
SMA: 6858.0 km
ECC: 0.0021
INC: 82.58 deg
RAAN: 236.43 deg
AOP: 220.73 deg
TA: 140.00 deg

ANALYSIS REQUIREMENTS
- Generate 20 fragments.
- Apply isotropic dispersion modeled as 1D velocity kicks.
- Delta-Vs: -100 m/s to +100 m/s (10 m/s steps, skip 0).
- Application: Purely along the V-bar (velocity) vector (Local VNB Frame).
- Propagation: 90 days.
- Perturbations: Earth J2 gravity ONLY.
DOCEOF

chown ga:ga /home/ga/Desktop/kosmos_1408_asat_event.txt

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

echo "=== Task Setup Complete: Event document at ~/Desktop/kosmos_1408_asat_event.txt ==="