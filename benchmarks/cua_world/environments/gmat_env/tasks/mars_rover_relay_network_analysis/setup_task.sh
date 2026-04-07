#!/bin/bash
set -euo pipefail

echo "=== Setting up mars_rover_relay_network_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/mars_relay_spec.txt
rm -f /home/ga/GMAT_output/mars_relay_analysis.script
rm -f /home/ga/GMAT_output/relay_summary.txt
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
cat > /home/ga/Desktop/mars_relay_spec.txt << 'SPECEOF'
============================================================
MARS RELAY NETWORK VISIBILITY ANALYSIS
Document: MRN-OPS-2026-042
============================================================

1. SIMULATION PARAMETERS
   Central Body:       Mars
   Epoch:              01 Jan 2026 12:00:00.000 UTC
   Duration:           7 Days
   Propagation Force:  Mars Point Mass (Primary body only)

2. SURFACE ASSET
   Name:               Perseverance
   Location:           Jezero Crater
   Latitude:           18.44 deg N
   Longitude:          77.45 deg E
   Min Elevation:      10.0 deg (Terrain/Antenna mask)

3. ORBITAL ASSET 1: MRO (Mars Reconnaissance Orbiter)
   Orbit Type:         Low Mars Orbit (Polar)
   Coordinate System:  Mars Equator (MJ2000Eq)
   Semi-Major Axis:    3676.0 km
   Eccentricity:       0.001
   Inclination:        92.9 deg
   RAAN:               0.0 deg
   AOP:                0.0 deg
   TA:                 0.0 deg

4. ORBITAL ASSET 2: MAVEN
   Orbit Type:         Highly Elliptical
   Coordinate System:  Mars Equator (MJ2000Eq)
   Semi-Major Axis:    6050.0 km
   Eccentricity:       0.42
   Inclination:        75.0 deg
   RAAN:               45.0 deg
   AOP:                270.0 deg  (Apocenter over Northern Hemisphere)
   TA:                 0.0 deg

5. REQUIRED OUTPUT FORMAT
   Create a text file at ~/GMAT_output/relay_summary.txt with EXACTLY:
   mro_total_minutes: <value>
   maven_total_minutes: <value>
   primary_relay: <MRO or MAVEN>
============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/mars_relay_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/mars_relay_spec.txt ==="