#!/bin/bash
set -euo pipefail

echo "=== Setting up geo_colocation_vector_separation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/colocation_directive.txt
rm -f /home/ga/GMAT_output/geo_colocation.script
rm -f /home/ga/GMAT_output/colocation_ephem.txt
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the colocation directive
cat > /home/ga/Desktop/colocation_directive.txt << 'DIREOF'
EUROPEAN SATELLITE OPERATIONS (EUROSAT)
FLIGHT DYNAMICS DIVISION
--------------------------------------------------
COLOCATION DIRECTIVE: 19.2 DEG EAST
DATE: 12 OCT 2025
STATUS: APPROVED FOR SIMULATION

OBJECTIVE: Validate e/i-vector separation for EuroSat-4 and EuroSat-8

ORBITAL SLOT: 19.2° East
COORDINATE SYSTEM: EarthMJ2000Eq

SPACECRAFT 1: EuroSat4 (Already on station)
  SMA:  42164.17 km
  ECC:  0.0004
  INC:  0.05 deg
  RAAN: 0.0 deg
  AOP:  0.0 deg
  TA:   0.0 deg

SPACECRAFT 2: EuroSat8 (Incoming)
  SMA:  42164.17 km
  ECC:  0.0004
  INC:  0.05 deg
  RAAN: 180.0 deg
  AOP:  0.0 deg
  TA:   180.0 deg

PROPAGATOR CONFIGURATION:
  Step Size: 3600 seconds (1 hour).

ANALYSIS REQUIREMENTS:
  Propagate both spacecraft SIMULTANEOUSLY for exactly 14 days.
  Record the X, Y, Z coordinates of both spacecraft at each step.
DIREOF

chown ga:ga /home/ga/Desktop/colocation_directive.txt

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

echo "=== Task Setup Complete: Colocation directive at ~/Desktop/colocation_directive.txt ==="