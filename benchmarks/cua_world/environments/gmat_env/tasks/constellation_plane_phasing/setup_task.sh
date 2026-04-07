#!/bin/bash
set -euo pipefail

echo "=== Setting up constellation_plane_phasing task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/plane_spacing_directive.txt
rm -f /home/ga/Documents/missions/plane_phasing.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the mission directive document
cat > /home/ga/Desktop/plane_spacing_directive.txt << 'EOF'
================================================================
CONSTELLATION MANAGEMENT DIRECTIVE - FLOCK-SPACING
================================================================
SPACECRAFT:      SAT-A (Reference), SAT-B (Maneuvering)
OBJECTIVE:       Establish 15.0 degree RAAN spacing

1. INITIAL STATE (Both Spacecraft)
   Epoch:        01 Mar 2026 12:00:00.000 UTC
   Coordinate System: EarthMJ2000Eq
   SMA:          6978.14 km  (approx 600 km altitude)
   ECC:          0.0001
   INC:          97.787 deg
   RAAN:         100.0 deg
   AOP:          0.0 deg
   TA:           0.0 deg

2. MANEUVER SEQUENCE FOR SAT-B
   Phase 1: Perform 2-burn sequence to lower orbit to 350 km circular (SMA = 6728.14 km).
   Phase 2: Coast (drift) in 350 km orbit until SAT-B RAAN is exactly 15.0 degrees greater than SAT-A RAAN.
   Phase 3: Perform 2-burn sequence to raise SAT-B back to 600 km circular.
   (Note: SAT-A remains in the 600 km orbit for the entire duration).

3. REQUIRED OUTPUTS
   Run the GMAT simulation and generate a report at ~/GMAT_output/phasing_results.txt
   The report must include exactly these keys (one per line):
   Drift_Duration_Days: [your calculated coast time in days]
   Total_DeltaV_ms: [sum of all 4 burns in meters/second]
   Final_RAAN_Diff_deg: [SAT_B RAAN - SAT_A RAAN at the end of the simulation]

4. MODELING CONSTRAINTS
   Force Model: Earth gravity only (JGM-2 or JGM-3, degree/order 4x4 minimum).
   Atmospheric drag: OFF (assume drag makeup is handled separately to isolate J2 effects).
   Point Masses: None required (Earth only).
================================================================
EOF

chown ga:ga /home/ga/Desktop/plane_spacing_directive.txt

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

echo "=== Task Setup Complete: Mission directive placed at ~/Desktop/plane_spacing_directive.txt ==="