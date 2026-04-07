#!/bin/bash
set -euo pipefail

echo "=== Setting up dsn_tracking_data_generation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/dsn_sim_specs.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the specification document
cat > /home/ga/Desktop/dsn_sim_specs.txt << 'SPECEOF'
MARS EXPLORER - NAVIGATION TRACKING SIMULATION
==============================================
Epoch: 01 Jun 2026 12:00:00.000 UTCG
Coordinate System: SunMJ2000Eq
Initial State (Cartesian, km and km/s):
  X  = 1.4959787e8
  Y  = 0.0
  Z  = 0.0
  VX = 0.0
  VY = 33.0
  VZ = 1.0

DSN STATION COORDINATES (Geodetic):
Goldstone (DSS-14):
  Latitude: 35.426 deg
  Longitude: 243.123 deg
  Altitude: 1.071 km
Canberra (DSS-43):
  Latitude: -35.401 deg
  Longitude: 148.981 deg
  Altitude: 0.688 km
Madrid (DSS-63):
  Latitude: 40.431 deg
  Longitude: 355.750 deg
  Altitude: 0.864 km

SIMULATION PARAMETERS:
  Duration: 7 Days
  Measurement Frequency: 3600 seconds
  Data Types: Range, RangeRate
SPECEOF

chown ga:ga /home/ga/Desktop/dsn_sim_specs.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/dsn_sim_specs.txt ==="