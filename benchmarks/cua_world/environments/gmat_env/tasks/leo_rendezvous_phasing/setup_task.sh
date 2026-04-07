#!/bin/bash
set -euo pipefail

echo "=== Setting up leo_rendezvous_phasing task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Documents/missions/rendezvous_phasing.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create a reference script showing the initial state (two spacecraft)
# This is a HINT file showing the initial orbital state the agent must start from.
# The agent's task is to create the phasing script from scratch.
cat > /home/ga/Documents/missions/initial_state_reference.txt << 'REFEOF'
=== Initial Orbital State for leo_rendezvous_phasing ===

Both spacecraft start in a 450 km altitude circular orbit around Earth.
CHIEF is the target spacecraft; CHASER is the servicer.

CHIEF Orbital Elements:
  Epoch: 01 Jan 2025 00:00:00.000 UTC
  CoordinateSystem: EarthMJ2000Eq
  SMA: 6821.14 km  (450 km altitude, Earth radius = 6371.14 km)
  ECC: 0.0001      (near-circular)
  INC: 28.5 deg    (KSC launch inclination)
  RAAN: 45.0 deg
  AOP: 0.0 deg
  TA: 0.0 deg      (CHIEF at reference point)

CHASER Orbital Elements:
  Epoch: 01 Jan 2025 00:00:00.000 UTC
  CoordinateSystem: EarthMJ2000Eq
  SMA: 6821.14 km
  ECC: 0.0001
  INC: 28.5 deg
  RAAN: 45.0 deg
  AOP: 0.0 deg
  TA: -14.84 deg   (CHASER is 100 km BEHIND CHIEF along-track)
                   (TA separation = 14.84 deg ≈ 100 km at this altitude)

Both spacecraft parameters:
  DryMass: 800 kg
  Cd: 2.2
  DragArea: 4.0 m^2
  Cr: 1.8
  SRPArea: 4.0 m^2

Desired end state:
  - CHASER 5 km trailing CHIEF in the same 450 km circular orbit
  - Total phasing time: the minimum needed for a 1-maneuver phasing ellipse

Note on phasing mechanics:
  - Lowering CHASER's orbit (decrease SMA) will cause it to orbit faster.
  - The drift rate (deg/orbit) = -3/2 * (delta_a / a) * n
  - For a ~10-15 km SMA reduction, phasing takes approximately 5-15 orbits.
  - One orbit at 450 km altitude ≈ 93.4 minutes.
REFEOF

chown ga:ga /home/ga/Documents/missions/initial_state_reference.txt

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

echo "=== Task Setup Complete: Initial state reference at ~/Documents/missions/initial_state_reference.txt ==="
