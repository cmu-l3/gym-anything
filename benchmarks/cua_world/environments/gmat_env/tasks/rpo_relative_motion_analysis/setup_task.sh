#!/bin/bash
set -euo pipefail

echo "=== Setting up rpo_relative_motion_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/envisat_inspection_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
cat > /home/ga/Desktop/envisat_inspection_spec.txt << 'SPECEOF'
================================================================
 PASSIVE SAFETY DRIFT TRAJECTORY SPECIFICATION
 Document: RPO-TRJ-044  Rev B   Date: 2026-03-10
================================================================

1. FORCE MODEL
   Central Body: Earth
   Gravity: Point Mass (Two-Body) only. (Do not include J2, drag, or SRP).

2. TARGET SPACECRAFT (ENVISAT_TARGET)
   Epoch:       01 Sep 2026 12:00:00.000 UTCG
   Coordinate:  EarthMJ2000Eq
   SMA:         7178.14 km
   ECC:         0.001
   INC:         98.5 deg
   RAAN:        45.0 deg
   AOP:         90.0 deg
   TA:          0.0 deg

3. SERVICER SPACECRAFT (CS_SERVICER)
   Epoch:       01 Sep 2026 12:00:00.000 UTCG
   Coordinate:  EarthMJ2000Eq
   SMA:         7177.14 km    (1 km lower to induce forward drift)
   ECC:         0.0011        (Eccentricity offset for radial separation)
   INC:         98.505 deg    (Inclination offset for cross-track separation)
   RAAN:        45.0 deg
   AOP:         90.0 deg
   TA:          -0.5 deg      (Starts approx 62 km behind the Target)

4. PROPAGATION
   Duration:    Exactly 24 hours (1 days)
   Step Size:   60 seconds

5. SUMMARY REPORT FORMAT
   Create /home/ga/GMAT_output/rpo_summary.txt with exactly these keys:
   min_range_km: <value>
   max_range_km: <value>
   passive_safety_violated: <true/false> (true if min_range_km < 0.5)
================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/envisat_inspection_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/envisat_inspection_spec.txt ==="