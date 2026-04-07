#!/bin/bash
set -euo pipefail

echo "=== Setting up ground_contact_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/earthwatch3_comms_plan.txt
rm -f /home/ga/Documents/missions/contact_analysis.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create mission requirements document
cat > /home/ga/Desktop/earthwatch3_comms_plan.txt << 'DOCEOF'
============================================================
EARTHWATCH-3 INITIAL CHECKOUT COMMUNICATIONS PLAN
Mission Operations Procedure Specification (MOPS)
Document: EW3-MOPS-COMM-2025-003
Date: 15 Feb 2025
============================================================

1. MISSION OVERVIEW

EarthWatch-3 is a polar-orbiting Earth observation satellite
launched into a sun-synchronous orbit for multispectral land
and ocean surface monitoring. This document specifies the
ground station contact analysis required for the 48-hour
Initial Orbit Checkout (IOC) phase.

2. SPACECRAFT ORBITAL PARAMETERS (Post-Separation)

   Epoch:               01 Mar 2025 10:30:00.000 UTC
   Coordinate System:   EarthMJ2000Eq
   Semi-Major Axis:     7078.14 km (altitude ~700 km)
   Eccentricity:        0.00105
   Inclination:         98.19 deg (sun-synchronous)
   RAAN:                148.52 deg
   Argument of Perigee: 90.0 deg
   True Anomaly:        0.0 deg

   Spacecraft Mass:     620 kg (dry)
   Drag Area:           6.2 m^2
   Cd:                  2.2
   SRP Area:           6.2 m^2
   Cr:                  1.4

3. GROUND STATION NETWORK

The following NASA Near-Earth Network (NEN) stations are
allocated for the EW3 IOC phase:

  Station ID  | Name           | Latitude     | Longitude      | Alt (km)
  ------------|----------------|--------------|----------------|--------
  SVLBRD      | Svalbard       | 78.2306 N    | 15.3897 E      | 0.458
  POKFLT      | Poker Flat     | 65.1260 N    | 147.4928 W     | 0.500
  MCMRDO      | McMurdo        | 77.8419 S    | 166.6863 E     | 0.010

  *Note: Poker Flat longitude is West, so in GMAT use -147.4928 or 212.5072.
  *Note: McMurdo latitude is South, so in GMAT use -77.8419.

  Minimum Elevation Angle: 5 degrees (for all stations)

4. ANALYSIS REQUIREMENTS

  - Compute ground station contact windows for all three
    stations over 48 hours from spacecraft epoch.
  - Summarize the number of passes, total contact minutes,
    and maximum elevation angle for each station.
  - Determine which station is the "Best_station" (most minutes).

============================================================
DOCEOF

chown ga:ga /home/ga/Desktop/earthwatch3_comms_plan.txt

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

echo "=== Task Setup Complete: Requirements doc at ~/Desktop/earthwatch3_comms_plan.txt ==="