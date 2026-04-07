#!/bin/bash
set -euo pipefail

echo "=== Setting up SSO LTAN Maintenance Campaign task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
rm -f /home/ga/Desktop/agrisat_initial_state.txt
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the initial state document on Desktop
cat > /home/ga/Desktop/agrisat_initial_state.txt << 'STATEEOF'
Spacecraft: AgriSat-1
Epoch: 01 Jun 2026 12:00:00.000 UTC
Coordinate System: EarthMJ2000Eq
SMA: 6971.14 km
ECC: 0.001
INC: 97.787 deg
RAAN: 65.0 deg
AOP: 0.0 deg
TA: 0.0 deg
Mass: 450 kg
STATEEOF

chown ga:ga /home/ga/Desktop/agrisat_initial_state.txt

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