#!/bin/bash
set -euo pipefail

echo "=== Setting up leo_drag_makeup_maneuvers task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Documents/missions/drag_makeup_reference.txt
rm -f /home/ga/Documents/missions/drag_makeup.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Write the reference document detailing the mission parameters
cat > /home/ga/Documents/missions/drag_makeup_reference.txt << 'REFEOF'
===============================================================
Mission Operations Parameter Reference: EOS-7
Document Type: Orbit Maintenance Specification
===============================================================

1. MISSION OVERVIEW
   Spacecraft: EOS-7 (Earth Observation Satellite 7)
   Mission: High-resolution optical imaging
   Operational Altitude: 500.0 km

2. INITIAL ORBITAL STATE
   Epoch: 01 Jan 2025 12:00:00.000 UTCG
   CoordinateSystem: EarthMJ2000Eq
   Semi-Major Axis (SMA): 6871.14 km
   Eccentricity (ECC): 0.00105
   Inclination (INC): 97.4 deg (Sun-Synchronous)
   RAAN: 22.5 deg
   Argument of Perigee (AOP): 90.0 deg
   True Anomaly (TA): 0.0 deg

3. SPACECRAFT PHYSICAL PARAMETERS
   Dry Mass: 150.0 kg
   Drag Area: 1.2 m^2
   Coefficient of Drag (Cd): 2.2
   SRP Area: 1.2 m^2
   Coefficient of Reflectivity (Cr): 1.4

4. FORCE MODEL REQUIREMENTS
   Central Body: Earth
   Gravity Field: Earth JGM-3 (or JGM-2), Degree/Order >= 10
   Atmosphere Model: JacchiaRoberts
   Space Weather: F10.7 = 150, F10.7A = 150, MagneticIndex = 3 (Moderate Solar)
   Point Masses: Sun, Luna
   Solar Radiation Pressure (SRP): On

5. MAINTENANCE STRATEGY
   - Propagate the spacecraft using the defined force model.
   - Altitude Deadband: The spacecraft must not drop more than 2 km below reference.
   - Trigger Condition: When SMA drops to 6869.14 km.
   - Maneuver: Execute an impulsive burn in the VNB Velocity direction.
   - Target Condition: Raise SMA back to exactly 6871.14 km.
   - Duration: Simulate this maintenance cycle for exactly 30 ElapsedDays.

===============================================================
END OF DOCUMENT
===============================================================
REFEOF

chown ga:ga /home/ga/Documents/missions/drag_makeup_reference.txt

# Launch GMAT
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

echo "=== Task Setup Complete: Reference document at ~/Documents/missions/drag_makeup_reference.txt ==="