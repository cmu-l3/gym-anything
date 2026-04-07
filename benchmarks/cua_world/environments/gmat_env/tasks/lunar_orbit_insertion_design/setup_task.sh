#!/bin/bash
set -euo pipefail

echo "=== Setting up lunar_orbit_insertion_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts and set up directories
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/lunar_mission_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create the mission specification document
cat > /home/ga/Desktop/lunar_mission_spec.txt << 'SPECEOF'
=======================================================
  PATHFINDER-L MISSION REQUIREMENTS BRIEF
  Prepared by: Cislunar Dynamics Division
  Date: 2025-06-10
  Classification: UNCLASSIFIED
=======================================================

MISSION OVERVIEW
  PathFinder-L is a lunar mapping and communications relay
  spacecraft to be placed in a low circular lunar orbit for
  a 1-year primary science mission.

LAUNCH PARAMETERS
  Launch Vehicle: Falcon 9 (Cape Canaveral SLC-40)
  Launch Date: 01 Jul 2025, 12:00:00.000 UTCG
  Parking Orbit Insertion:
    Altitude: 185 km circular (SMA = 6556.14 km)
    Inclination: 28.5 deg
    RAAN: 0.0 deg
    AOP: 0.0 deg
    True Anomaly at TLI: 0.0 deg

SPACECRAFT PARAMETERS
  Dry Mass: 580 kg
  Fuel Mass: 320 kg (bipropellant)
  SRP Area: 4.2 m^2
  Cr: 1.8
  Cd: 2.2

TARGET LUNAR ORBIT
  Type: Circular, near-polar
  Altitude: 100 km above mean lunar surface
  Inclination: 90 deg (polar, Moon-centered)

DELTA-V BUDGET ALLOCATION (Reference)
  TLI: ~3100 m/s (from heritage Apollo/LRO data)
  LOI: ~850 m/s (from heritage data)
  Total: ~3950 m/s
  Note: These are reference values. Actual values depend
  on trajectory geometry and must be determined by
  simulation.

PROPAGATION REQUIREMENTS
  - Earth gravity: at minimum point-mass (JGM-2 or higher
    recommended for LEO phase)
  - Lunar gravity: point-mass (LP165P optional)
  - Solar gravity: recommended for cislunar accuracy
  - SRP: optional but recommended

DELIVERABLES
  1. GMAT script implementing the full TLI-to-LOI sequence
  2. Mission results report with achieved delta-V values,
     transfer time, and final lunar orbit parameters
  Output path: ~/GMAT_output/lunar_transfer_results.txt
=======================================================
SPECEOF

chown ga:ga /home/ga/Desktop/lunar_mission_spec.txt

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