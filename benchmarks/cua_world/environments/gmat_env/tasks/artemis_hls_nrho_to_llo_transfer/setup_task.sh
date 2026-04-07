#!/bin/bash
set -euo pipefail

echo "=== Setting up artemis_hls_nrho_to_llo_transfer task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/hls_mission_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create the Artemis HLS mission spec
cat > /home/ga/Desktop/hls_mission_spec.txt << 'SPECEOF'
===============================================================
ARTEMIS HUMAN LANDING SYSTEM (HLS) MISSION SPECIFICATION
Phase: NRHO Proxy to LLO Transfer
Prepared by: NASA Flight Dynamics Facility
Date: 2026-03-10
===============================================================

1. MISSION OVERVIEW
   The HLS spacecraft is currently stationed in a highly elliptical
   lunar polar orbit, serving as a proxy for the Near Rectilinear 
   Halo Orbit (NRHO). The spacecraft must perform a two-impulse
   maneuver to transfer down to a 100 km circular Low Lunar Orbit
   (LLO) in preparation for powered descent.

2. INITIAL STATE (NRHO PROXY)
   Coordinate System: Luna-Centered, EarthMJ2000Eq axes
   (Ensure GMAT's spacecraft origin is set to 'Luna')
   Epoch: 01 Jan 2026 12:00:00.000 UTCG
   
   Keplerian Elements:
     Semi-Major Axis (SMA): 38440.0 km
     Eccentricity (ECC): 0.88
     Inclination (INC): 90.0 deg
     RAAN: 0.0 deg
     Argument of Perigee (AOP): 90.0 deg
     True Anomaly (TA): 0.0 deg (Spacecraft is currently at Perilune)

3. SPACECRAFT PARAMETERS
   Dry Mass: 15000 kg
   Propellant Mass: 30000 kg
   Total Mass: 45000 kg
   Cd: 2.2
   Cr: 1.8
   Drag Area: 40.0 m^2
   SRP Area: 40.0 m^2

4. FORCE MODEL
   Central Body: Luna
   Primary Bodies: {Luna} (Point Mass is sufficient for this analysis)
   Drag/SRP: Off

5. MANEUVER SEQUENCE (TWO-IMPULSE)
   Step 1: Propagate from the initial state to Apoapsis.
   Step 2: Perform Burn 1 (at Apoapsis) using a DifferentialCorrector to
           vary the V-direction velocity. Target a Perilune radius of
           1838.14 km (Luna radius 1738.14 km + 100 km altitude).
   Step 3: Propagate to the new Periapsis.
   Step 4: Perform Burn 2 (at Periapsis) using a DifferentialCorrector to
           vary the V-direction velocity. Target an Eccentricity of 0.0 
           (circularize the orbit).

6. REQUIRED DELIVERABLES
   - GMAT Script saved to: ~/GMAT_output/hls_transfer_script.script
   - Results text file saved to: ~/GMAT_output/hls_transfer_results.txt
   
   The results file must contain exactly the following lines:
   Burn1_DeltaV_mps: <value>
   Burn2_DeltaV_mps: <value>
   Total_DeltaV_mps: <value>
   Final_SMA_km: <value>
   Final_ECC: <value>

===============================================================
END OF DOCUMENT
===============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/hls_mission_spec.txt

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

echo "=== Task Setup Complete ==="