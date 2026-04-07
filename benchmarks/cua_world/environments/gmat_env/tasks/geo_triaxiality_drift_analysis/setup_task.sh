#!/bin/bash
set -euo pipefail

echo "=== Setting up geo_triaxiality_drift_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/geo_drift_requirements.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write requirements document to Desktop
cat > /home/ga/Desktop/geo_drift_requirements.txt << 'SPECEOF'
GEO DRIFT ANALYSIS REQUIREMENTS
===============================
Spacecraft: DEFUNCT-GEO-1
Epoch: 01 Jan 2026 00:00:00.000 UTC
Orbit Type: Geosynchronous (GEO)
Semi-Major Axis: 42164.17 km
Eccentricity: 0.0
Inclination: 0.0 deg
Initial Geographic Longitude: 350.0 deg East (equivalent to 10.0 deg West)
Propagation Duration: 730 Days

Required Physics Model:
Central Body: Earth
Gravity Model: EGM96 or JGM-2
Minimum Degree and Order: 4
Note: Point Mass or J2-only models will result in zero triaxial drift and invalidate the analysis.
SPECEOF

chown ga:ga /home/ga/Desktop/geo_drift_requirements.txt

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

echo "=== Task Setup Complete: Requirements at ~/Desktop/geo_drift_requirements.txt ==="