#!/bin/bash
set -euo pipefail

echo "=== Setting up gravity_model_sensitivity task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Documents/missions/gravity_study.script
rm -f /home/ga/Documents/missions/gravity_study_initial_state.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write initial state document to Documents/missions
cat > /home/ga/Documents/missions/gravity_study_initial_state.txt << 'STATEEOF'
=== GRAVITY MODEL SENSITIVITY STUDY ===
=== Spacecraft Initial Conditions ===

Mission: GravSens-LEO (Earth Observation Trade Study)
Prepared by: Mission Analysis Division
Date: 2025-01-01

Spacecraft: Sentinel-EO
  CoordinateSystem: EarthMJ2000Eq
  DateFormat: UTCGregorian
  Epoch: 01 Jan 2025 00:00:00.000

  Orbital Elements (Keplerian):
    SMA  = 6871.14 km   (500 km altitude, circular)
    ECC  = 0.001
    INC  = 97.4 deg     (sun-synchronous)
    RAAN = 0.0 deg
    AOP  = 0.0 deg
    TA   = 0.0 deg

  Physical Properties:
    DryMass  = 150 kg
    Cd       = 2.2
    DragArea = 1.5 m^2
    Cr       = 1.8
    SRPArea  = 1.5 m^2

Study Requirements:
  - Propagate for 7 days under gravity-only force models
  - Compare truncation levels: J2-only (2x0), 4x4, 12x12, 70x70 (reference)
  - No drag, SRP, or third-body forces (isolate gravity effects)
  - Report RSS position divergence of each model vs. 70x70 reference
  - Output: ~/GMAT_output/gravity_sensitivity_report.txt

Notes:
  - Use JGM2 or JGM3 potential file (included with GMAT)
  - Earth equatorial radius: 6378.1363 km
  - Earth gravitational parameter: 398600.4415 km^3/s^2
STATEEOF

chown ga:ga /home/ga/Documents/missions/gravity_study_initial_state.txt

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