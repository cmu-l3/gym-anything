#!/bin/bash
set -euo pipefail

echo "=== Setting up ccsds_ephemeris_export task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/magsat2_state.txt
rm -f /home/ga/Documents/missions/magsat2_ephemeris.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write state vector document to Desktop
cat > /home/ga/Desktop/magsat2_state.txt << 'SPECEOF'
====================================================
MagSat-2 Flight Dynamics State Vector
====================================================
Spacecraft Name: MagSat2
Epoch:           01 Sep 2025 12:00:00.000 UTCG
Frame:           EarthMJ2000Eq

-- Keplerian Elements --
SMA:  42000.0 km
ECC:  0.82
INC:  63.4 deg
RAAN: 180.0 deg
AOP:  270.0 deg
TA:   0.0 deg

-- Physical Properties --
Dry Mass:   1200 kg
Drag Area:  4.0 m^2
Cd:         2.2
SRP Area:   15.0 m^2
Cr:         1.5

-- Required Force Model for Predicts --
Central Body:  Earth
Gravity Model: JGM-2 (Degree 10, Order 10)
Third Bodies:  Sun, Luna
Drag Model:    JacchiaRoberts
SRP:           Enabled
====================================================
SPECEOF

chown ga:ga /home/ga/Desktop/magsat2_state.txt

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

echo "=== Task Setup Complete: State vector at ~/Desktop/magsat2_state.txt ==="