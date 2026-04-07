#!/bin/bash
set -euo pipefail

echo "=== Setting up gps_graveyard_disposal task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
rm -f /home/ga/Desktop/gps_disposal_directive.txt
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write disposal directive document
cat > /home/ga/Desktop/gps_disposal_directive.txt << 'DOCEOF'
================================================================
UNITED STATES SPACE FORCE — SPACE DELTA 8
GPS CONSTELLATION MANAGEMENT OFFICE
================================================================
DISPOSAL DIRECTIVE: GPS SVN-72 (Block IIF, PRN 10)
Classification: UNCLASSIFIED
Date: 15 Mar 2025

1. DIRECTIVE
   GPS SVN-72 has reached end of operational life (15 years). Per
   IADC Space Debris Mitigation Guidelines (IADC-02-01 Rev 3) and
   USSPACECOM Instruction 10-47, this vehicle shall be maneuvered
   to a disposal (graveyard) orbit no less than 500 km above the
   GPS operational constellation semi-major axis.

2. CURRENT ORBITAL STATE (Epoch: 15 Mar 2025 00:00:00.000 UTC)
   Coordinate System: EarthMJ2000Eq
   Semi-Major Axis:     26559.7 km
   Eccentricity:        0.0038
   Inclination:         55.1 deg
   RAAN:                197.4 deg
   Argument of Perigee: 312.8 deg
   True Anomaly:        45.6 deg

3. SPACECRAFT PROPERTIES
   Dry Mass:            1630 kg
   Remaining Fuel:      52 kg (hydrazine)
   Drag Coefficient:    2.2
   Cross-Section Area:  20.0 m^2
   SRP Area:            22.5 m^2
   SRP Coefficient:     1.8
   Thruster Isp:        220 s (blowdown, monopropellant hydrazine)

4. DISPOSAL REQUIREMENTS
   a. Graveyard orbit SMA shall exceed 27059.7 km
      (minimum 500 km above operational SMA of 26559.7 km)
   b. Graveyard orbit eccentricity shall not exceed 0.01
      (prevents re-entry into constellation altitude band)
   c. Total disposal Delta-V shall not exceed available fuel budget
   d. Post-disposal orbit shall be verified stable for minimum 30 days

5. FORCE MODEL REQUIREMENTS
   Propagation shall include:
   - Earth point mass (minimum) or JGM-2/JGM-3 gravity (preferred)
   - Solar radiation pressure
   - Third-body perturbations (Sun, Moon) recommended for 30-day stability check

6. REPORTING
   Disposal report shall include: initial SMA, final SMA, total
   Delta-V (m/s), fuel consumed (kg), final eccentricity, and
   compliance determination.
================================================================
DOCEOF

chown ga:ga /home/ga/Desktop/gps_disposal_directive.txt

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