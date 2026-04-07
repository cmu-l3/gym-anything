#!/bin/bash
set -euo pipefail

echo "=== Setting up lisa_interferometer_formation_stability task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/lisa_orbital_parameters.txt
rm -rf /home/ga/GMAT_output
rm -rf /home/ga/Documents/missions
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write LISA parameters document to Desktop
# These are the actual nominal Keplerian parameters for the 2.5 Gm LISA baseline
cat > /home/ga/Desktop/lisa_orbital_parameters.txt << 'SPECEOF'
LISA OBSERVATORY NOMINAL ORBITAL PARAMETERS
Reference Epoch: 01 Jan 2035 00:00:00.000 UTC
Central Body: Sun
Reference Frame: Sun-Centered J2000 Ecliptic (MJ2000Ec)

COMMON PARAMETERS (All Spacecraft):
Semi-Major Axis (SMA):  149597870.7 km (1.0 AU)
Eccentricity (ECC):     0.004823
Inclination (INC):      0.4786 deg (relative to Ecliptic)

SPACECRAFT 1 (LISA1):
Right Ascension of Ascending Node (RAAN): 0.0 deg
Argument of Periapsis (AOP):              0.0 deg
Mean Anomaly (MA):                        0.0 deg

SPACECRAFT 2 (LISA2):
Right Ascension of Ascending Node (RAAN): 120.0 deg
Argument of Periapsis (AOP):              240.0 deg
Mean Anomaly (MA):                        240.0 deg

SPACECRAFT 3 (LISA3):
Right Ascension of Ascending Node (RAAN): 240.0 deg
Argument of Periapsis (AOP):              120.0 deg
Mean Anomaly (MA):                        120.0 deg

CRITICAL NOTE: You must input Mean Anomaly (MA) into the orbit state, not the default True Anomaly (TA). If you use TA, the formation will not form an equilateral triangle and will drift apart immediately.
CRITICAL NOTE 2: You must create a custom Coordinate System in GMAT to input these elements correctly (Origin: Sun, Axes: MJ2000Ec).
SPECEOF

chown ga:ga /home/ga/Desktop/lisa_orbital_parameters.txt

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

echo "=== Task Setup Complete: LISA parameters at ~/Desktop/lisa_orbital_parameters.txt ==="