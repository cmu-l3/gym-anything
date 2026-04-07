#!/bin/bash
set -euo pipefail

echo "=== Setting up suborbital_splashdown_dispersion task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean workspace
rm -f /home/ga/Desktop/payload_range_safety_spec.txt
rm -f /home/ga/GMAT_output/splashdown_sim.script
rm -f /home/ga/GMAT_output/dispersion_results.txt
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# Record start time
date +%s > /tmp/task_start_time.txt

# Create spec file
cat > /home/ga/Desktop/payload_range_safety_spec.txt << 'SPECEOF'
=== RANGE SAFETY TRAJECTORY SPECIFICATION ===
MISSION: SR-2026-X (Black Brant XII Payload)
AGENCY: Wallops Flight Facility Range Safety

BURNOUT STATE (INITIAL CONDITIONS):
Epoch: 15 Jun 2026 14:00:00.000 UTCG
Reference Frame: EarthFixed
State Type: Spherical AZ/FPA
Radius (RMAG): 6528.14 km
Longitude (RA): -75.48 deg
Latitude (DEC): 37.83 deg
Velocity (VMAG): 3.50 km/s
Azimuth (AZI): 135.0 deg
Flight Path Angle (FPA): 70.0 deg

PAYLOAD PROPERTIES:
Dry Mass: 300.0 kg
Drag Area: 0.8 m^2

ANALYSIS REQUIREMENTS:
Perform a 3-case bounding analysis to establish the splashdown dispersion footprint. 
Propagate each case to Earth surface impact (Altitude = 0 km) using Earth gravity 
and atmospheric drag.

Case 1 (Nominal): Cd = 2.2
Case 2 (Low Drag): Cd = 1.2
Case 3 (High Drag): Cd = 3.2
SPECEOF

chown ga:ga /home/ga/Desktop/payload_range_safety_spec.txt

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