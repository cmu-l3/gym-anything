#!/bin/bash
set -euo pipefail

echo "=== Setting up lunar_orbit_stability_mascons task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace and ensure directories exist
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/lunar_orbits.txt
rm -f /home/ga/GMAT_output/lunar_stability.script
rm -f /home/ga/GMAT_output/lunar_stability_report.txt
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create the mission specification document
cat > /home/ga/Desktop/lunar_orbits.txt << 'SPECEOF'
===============================================================
LUNAR PARKING ORBIT STABILITY ANALYSIS
===============================================================

1. BACKGROUND
The Moon's gravitational field is highly uneven due to mass
concentrations (mascons). Low, circular orbits rapidly become
eccentric and crash into the surface. However, certain "frozen"
orbits remain stable for long durations without station-keeping.

2. SPACECRAFT 1: Sat_Circular
   - Epoch: 01 Jan 2025 12:00:00.000 UTC
   - Coordinate System: Moon-Centered (e.g., Luna-MJ2000Eq)
   - SMA: 1787.4 km (50 km altitude, Moon radius = 1737.4 km)
   - ECC: 0.0
   - INC: 86.0 deg
   - RAAN: 0.0 deg
   - AOP: 0.0 deg
   - TA: 0.0 deg
   - Mass: 1000 kg, Cd: 2.2, DragArea: 15 m^2 (drag is negligible)

3. SPACECRAFT 2: Sat_Frozen
   - Epoch: 01 Jan 2025 12:00:00.000 UTC
   - Coordinate System: Moon-Centered
   - SMA: 1787.4 km
   - ECC: 0.03
   - INC: 86.0 deg
   - RAAN: 0.0 deg
   - AOP: 90.0 deg  <-- Key parameter for lunar frozen orbits
   - TA: 0.0 deg
   - Mass/Area: Same as above

4. ENVIRONMENT SETTINGS
   - Central Body: Luna
   - Gravity Model: LP165P (or similar lunar model)
   - Gravity Degree: 20
   - Gravity Order: 20
   (High order is required to simulate mascon perturbations)

5. PROPAGATION REQUIREMENTS
   - Sat_Circular: Propagate until Altitude <= 0 OR 60 days elapsed.
   - Sat_Frozen: Propagate for 60 days.
SPECEOF

chown ga:ga /home/ga/Desktop/lunar_orbits.txt

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
    
    # Take initial screenshot
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete ==="