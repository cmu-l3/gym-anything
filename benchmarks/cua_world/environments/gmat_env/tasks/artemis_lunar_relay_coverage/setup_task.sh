#!/bin/bash
set -euo pipefail

echo "=== Setting up artemis_lunar_relay_coverage task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/artemis_relay_reqs.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the requirements document
cat > /home/ga/Desktop/artemis_relay_reqs.txt << 'REQEOF'
================================================================
ARTEMIS LUNAR COMMUNICATIONS RELAY
Orbit Design & Coverage Requirements
================================================================

1. SPACECRAFT ORBIT
   Central Body:        Luna (Moon)
   Orbital Period:      12.0 hours
   Eccentricity:        0.60
   Inclination:         85.0 degrees
   Argument of Perigee: 90.0 degrees (Apolune over South Pole)
   RAAN:                0.0 degrees
   True Anomaly:        180.0 degrees (Start at Apolune)
   Epoch:               01 Jan 2026 12:00:00.000 UTC

2. GROUND SEGMENT
   Facility Name:       ShackletonBase
   Central Body:        Luna
   Latitude:            -89.9 deg
   Longitude:           0.0 deg
   Altitude:            0.0 km
   Minimum Elevation:   5.0 degrees

3. ANALYSIS REQUIREMENTS
   - Use a Point Mass gravity model for Luna
   - Propagate for exactly 7 days
   - Generate a contact location report
   - Create a summary of the longest continuous contact duration
     (A 12-hour highly elliptical orbit with e=0.6 and apolune 
     over the South Pole should provide long dwell times > 8 hours
     per orbit).

================================================================
END OF DOCUMENT
================================================================
REQEOF

chown ga:ga /home/ga/Desktop/artemis_relay_reqs.txt

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

echo "=== Task Setup Complete: Requirements document at ~/Desktop/artemis_relay_reqs.txt ==="