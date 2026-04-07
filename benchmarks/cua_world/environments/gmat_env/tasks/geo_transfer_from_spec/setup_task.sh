#!/bin/bash
set -euo pipefail

echo "=== Setting up geo_transfer_from_spec task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/geo_sat_specs.txt
rm -f /home/ga/Documents/missions/geo_transfer.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
# CommStar-7 is a fictional but physically realistic GEO comms satellite
# GTO parameters correspond to a standard Ariane 5 GTO injection
cat > /home/ga/Desktop/geo_sat_specs.txt << 'SPECEOF'
===============================================================
CommStar-7 Satellite Mission Specifications
Satellite Operator: CommStar Networks Ltd.
Document ID: CST7-MOPS-001-Rev-B
Classification: Unclassified — Distribution Unlimited
===============================================================

1. MISSION OVERVIEW
   CommStar-7 is a high-throughput Ka-band geostationary communications satellite
   providing broadband internet to North America and Europe.
   Target Orbital Slot: 101.2 deg West Longitude (GEO)

2. LAUNCH VEHICLE AND INJECTION ORBIT (GTO)
   Launch Vehicle: Ariane 5 ECA
   Launch Date: 15 Jun 2025 22:30:00.000 UTC
   Injection Orbit (GTO):
     Semi-Major Axis (SMA): 24505.4 km
     Eccentricity (ECC): 0.7315
     Inclination (INC): 7.0 deg
     RAAN: 15.0 deg
     Argument of Perigee (AOP): 178.0 deg
     True Anomaly (TA): 0.0 deg (at perigee)
   Coordinate System: EarthMJ2000Eq

3. SPACECRAFT PARAMETERS
   Dry Mass: 2840 kg
   Propellant Mass at Launch: 1850 kg
   Total Launch Mass: 4690 kg
   Isp (Apogee Engine): 318 s
   Thrust (Apogee Engine): 400 N
   Drag Coefficient (Cd): 2.2
   Reflectivity Coefficient (Cr): 1.4
   Drag Area: 15.0 m^2
   SRP Area: 60.0 m^2

4. TARGET GEOSTATIONARY ORBIT
   Semi-Major Axis: 42164.17 km
   Eccentricity: < 0.0005
   Inclination: < 0.05 deg
   Longitude: 101.2 deg West

5. MISSION SEQUENCE
   Step 1: Propagate from GTO injection to apogee
   Step 2: Apply Apogee Kick Maneuver (AKM) — impulsive burn in velocity direction
           at apogee to raise perigee and achieve GEO insertion
   Step 3: Propagate in GEO for 1 day to verify station keeping

   Note: For this analysis, use an impulsive burn model.
         Use a DifferentialCorrector to precisely target GEO SMA = 42164.17 km.

6. OUTPUTS REQUIRED
   The simulation shall produce:
   - Apogee Kick Delta-V (DeltaV2_mps)
   - Final GEO SMA (GEO_SMA_km)
   - Final GEO Eccentricity (GEO_ECC)
   - Final GEO Inclination (GEO_INC_deg)

===============================================================
END OF DOCUMENT
CommStar Networks Ltd. — Proprietary
===============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/geo_sat_specs.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/geo_sat_specs.txt ==="
