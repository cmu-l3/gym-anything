#!/bin/bash
set -euo pipefail

echo "=== Setting up constellation_spare_phasing task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/phasing_maneuver_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the Constellation Specification Document
cat > /home/ga/Desktop/phasing_maneuver_spec.txt << 'SPECEOF'
================================================================
 CONSTELLATION REPLENISHMENT DIRECTIVE
================================================================
Event: Replacement of failed node in Plane 3
Date: 01 Jan 2026 12:00:00.000 UTC

1. TARGET SLOT (Nominal Constellation Orbit)
   SMA: 7571.14 km (1200 km altitude)
   ECC: 0.0
   INC: 87.9 deg
   RAAN: 0.0 deg
   AOP: 0.0 deg
   TA: 180.0 deg

2. ON-ORBIT SPARE
   SMA: 7471.14 km (1100 km altitude)
   ECC: 0.0
   INC: 87.9 deg
   RAAN: 0.0 deg
   AOP: 0.0 deg
   TA: 0.0 deg

3. CONSTRAINTS & CONFIGURATION
   - Force Model: Two-Body (Point Mass Earth)
   - Transfer Type: Impulsive Two-Burn Hohmann
   - Phasing Tolerance: Final TA difference <= 0.5 degrees
   - SMA Tolerance: Final SMA matches target within 1.0 km
SPECEOF

chown ga:ga /home/ga/Desktop/phasing_maneuver_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/phasing_maneuver_spec.txt ==="