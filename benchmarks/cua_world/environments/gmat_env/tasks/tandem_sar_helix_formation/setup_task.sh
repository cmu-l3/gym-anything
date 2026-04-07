#!/bin/bash
set -euo pipefail

echo "=== Setting up tandem_sar_helix_formation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/sar_formation_specs.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the mission specification document
cat > /home/ga/Desktop/sar_formation_specs.txt << 'SPECEOF'
=== GeoSAR-Tandem Mission Specification ===

CHIEF SATELLITE (GeoSAR-1) REFERENCE ORBIT:
SMA:  6892.14 km
ECC:  0.0
INC:  97.4 deg
RAAN: 45.0 deg
AOP:  0.0 deg
TA:   0.0 deg

DEPUTY SATELLITE (GeoSAR-2) REQUIREMENTS:
To maintain a stable helix for interferometry without secular drift:
1. Deputy must have EXACTLY the same Semi-Major Axis (SMA) and Inclination (INC) as the Chief.
2. Target Max Radial baseline: ~500 meters (0.5 km)
3. Target Max Cross-track baseline: ~2500 meters (2.5 km)
4. AOP and TA must remain 0.0 deg.

RELATIVE ORBIT FORMULAS:
- Radial Amplitude (km) ≈ SMA * delta_ECC
- Cross-track Amplitude (km) ≈ SMA * sin(INC) * delta_RAAN_radians

Use these formulas to compute the Deputy's ECC and RAAN, then build the GMAT simulation.
SPECEOF

chown ga:ga /home/ga/Desktop/sar_formation_specs.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/sar_formation_specs.txt ==="