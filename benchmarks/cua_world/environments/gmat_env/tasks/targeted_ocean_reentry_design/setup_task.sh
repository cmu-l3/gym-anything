#!/bin/bash
set -euo pipefail

echo "=== Setting up targeted_ocean_reentry_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/satellite_disposal_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create the Specification Document
cat > /home/ga/Desktop/satellite_disposal_spec.txt << 'SPECEOF'
================================================================
AQUA-TERRA-2 END OF LIFE DISPOSAL SPECIFICATION
Document: AT2-EOL-2026-004
Date: 10 March 2026
================================================================

1. SPACECRAFT PARAMETERS
   Mass:             4500 kg
   Drag Area:        15.0 m^2
   Cd:               2.2

2. INITIAL ORBITAL STATE (EarthMJ2000Eq)
   Epoch:            15 Mar 2026 00:00:00.000 UTCG
   SMA:              7071.14 km  (~700 km altitude)
   ECC:              0.0001
   INC:              98.2 deg
   RAAN:             125.0 deg
   AOP:              0.0 deg
   TA:               45.0 deg

3. DISPOSAL TARGET (SPOUA "Point Nemo" Bounding Box)
   Reentry interface is defined as 80.0 km altitude.
   At exactly 80.0 km altitude, the spacecraft must be located within:
   
   Target Latitude:  -55.0 deg to -35.0 deg  (South)
   Target Longitude: 220.0 deg to 250.0 deg  (East)
                     *Note: GMAT may report this as -140.0 to -110.0 deg. Both are acceptable.

4. REQUIRED DELIVERABLES
   A. GMAT Script: ~/GMAT_output/targeted_reentry.script
   
   B. GMAT Trajectory Report: ~/GMAT_output/reentry_trajectory.txt
      Must contain EXACTLY these columns in order:
      - Spacecraft.ElapsedDays
      - Spacecraft.Earth.Altitude
      - Spacecraft.Earth.Latitude
      - Spacecraft.Earth.Longitude
      
   C. Summary Report: ~/GMAT_output/disposal_summary.txt
      Must contain:
      - DeltaV_Magnitude_ms: <value>
      - Reentry_Latitude: <value>
      - Reentry_Longitude: <value>
================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/satellite_disposal_spec.txt

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