#!/bin/bash
set -euo pipefail

echo "=== Setting up iss_high_beta_thermal_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output/*
rm -f /home/ga/Desktop/iss_state_memo.txt
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the ISS state memo on the Desktop
cat > /home/ga/Desktop/iss_state_memo.txt << 'MEMOEOF'
================================================================
SPACE STATION ORBITAL STATE & THERMAL CONSTRAINT MEMO
================================================================
Target: International Space Station (ISS)
Epoch: 01 Jan 2026 00:00:00.000 UTCG

INITIAL ORBITAL STATE (EarthMJ2000Eq)
  SMA:  6790.0 km
  ECC:  0.0005
  INC:  51.64 deg
  RAAN: 120.0 deg
  AOP:  0.0 deg
  TA:   0.0 deg

THERMAL CONSTRAINTS
  The ISS thermal radiator and solar array articulation systems
  enter "High Beta" operational mode whenever the absolute
  value of the solar beta angle exceeds 60.0 degrees.
================================================================
MEMOEOF

chown ga:ga /home/ga/Desktop/iss_state_memo.txt

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

echo "=== Task Setup Complete: Memo written to ~/Desktop/iss_state_memo.txt ==="