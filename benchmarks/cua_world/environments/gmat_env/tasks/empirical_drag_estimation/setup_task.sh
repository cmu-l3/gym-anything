#!/bin/bash
set -euo pipefail

echo "=== Setting up empirical_drag_estimation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/decay_data.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create observation data file
cat > /home/ga/Desktop/decay_data.txt << 'EOF'
OBJECT: SL-8 R/B (Kosmos-3M Stage 2, NORAD 14130)
DRY MASS: 1430 kg
DRAG AREA: 10.5 m^2

OBSERVATION 1 (INITIAL STATE):
Epoch: 01 Jun 2024 12:00:00.000 UTCGregorian
Coordinate System: EarthMJ2000Eq
SMA: 6760.00 km
ECC: 0.001
INC: 83.00 deg
RAAN: 120.00 deg
AOP: 45.00 deg
TA: 0.00 deg

OBSERVATION 2 (TARGET STATE):
Epoch: 01 Jul 2024 12:00:00.000 UTCGregorian (30 days elapsed)
Target SMA: 6735.20 km
EOF

chown ga:ga /home/ga/Desktop/decay_data.txt

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

echo "=== Task Setup Complete: Data placed at ~/Desktop/decay_data.txt ==="