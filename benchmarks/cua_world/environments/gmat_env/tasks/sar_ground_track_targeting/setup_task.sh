#!/bin/bash
set -euo pipefail

echo "=== Setting up sar_ground_track_targeting task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean workspace
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/overflight_spec.txt
rm -f /home/ga/Documents/missions/sar_targeting.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Write spec document to Desktop
cat > /home/ga/Desktop/overflight_spec.txt << 'SPECEOF'
======================================================
     EMERGENCY OVERFLIGHT TASKING SPECIFICATION
======================================================

SATELLITE INITIAL STATE
-----------------------
Name: SAR_1
Epoch: 01 Jan 2026 12:00:00.000 UTCG
Coordinate System: EarthMJ2000Eq
SMA: 6878.14 km
ECC: 0.001
INC: 97.4 deg
RAAN: 45.0 deg
AOP: 0.0 deg
TA: 0.0 deg
DryMass: 850 kg
DragArea: 2.5 m^2
Cd: 2.2
Cr: 1.8
SRPArea: 2.5 m^2

TARGET GEOGRAPHY
----------------
Target Name: Philadelphia, PA, USA
Target Latitude: 40.0 deg
Target Longitude: -75.0 deg
Target Pass Window: ~2.8 days after epoch

MANEUVER CONSTRAINTS
--------------------
Type: Impulsive Burn
Direction: Along-track (Velocity direction, local VNB)
Execution: At initial epoch

REQUIREMENTS
------------
Targeting: Use a Differential Corrector. 
Vary the burn's velocity direction.
Propagate exactly 2.8 days first, then propagate to the target Latitude (40.0 deg).
Achieve the target Longitude (-75.0 deg) within 0.05 deg tolerance.
======================================================
SPECEOF

chown ga:ga /home/ga/Desktop/overflight_spec.txt

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