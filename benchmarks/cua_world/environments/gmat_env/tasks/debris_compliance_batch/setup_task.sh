#!/bin/bash
set -euo pipefail

echo "=== Setting up debris_compliance_batch task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/debris_manifest.csv
rm -f /home/ga/Documents/missions/debris_batch_analysis.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create debris manifest CSV
# SAT_A: 600 km, small sat -> COMPLIANT (~15-20 years lifetime)
# SAT_B: 1200 km, large sat -> NON_COMPLIANT (>25 years)
# SAT_C: 500 km, medium sat -> COMPLIANT (~8-12 years)
# SAT_D: 900 km, medium sat -> NON_COMPLIANT (>25 years)
# SAT_E: 400 km, small sat -> COMPLIANT (~2-5 years)
cat > /home/ga/Desktop/debris_manifest.csv << 'CSVEOF'
SatelliteName,SMA_km,ECC,INC_deg,DryMass_kg,DragArea_m2,Cd,Description
SAT_A,6971.14,0.001,98.0,120,2.0,2.2,Earth Observation Cubesat 600km SSO
SAT_B,7571.14,0.001,55.0,2500,15.0,2.2,Large Communications Platform 1200km MEO
SAT_C,6871.14,0.001,97.5,80,1.5,2.2,Technology Demonstration 500km SSO
SAT_D,7271.14,0.001,65.0,1800,12.0,2.2,Remote Sensing Satellite 900km
SAT_E,6771.14,0.001,98.5,45,0.8,2.2,Nanosatellite 400km SSO
CSVEOF

chown ga:ga /home/ga/Desktop/debris_manifest.csv

# 4. Write ground truth note for operator reference (not visible to agent)
cat > /tmp/ground_truth_debris.json << 'GTEOF'
{
    "SAT_A": {"altitude_km": 600, "compliant": true, "note": "600km, Cd*A/m = 0.0333, ~18yr"},
    "SAT_B": {"altitude_km": 1200, "compliant": false, "note": "1200km, too high, >100yr"},
    "SAT_C": {"altitude_km": 500, "compliant": true, "note": "500km, Cd*A/m = 0.0375, ~10yr"},
    "SAT_D": {"altitude_km": 900, "compliant": false, "note": "900km, Cd*A/m = 0.0107, >25yr"},
    "SAT_E": {"altitude_km": 400, "compliant": true, "note": "400km, Cd*A/m = 0.0391, ~3yr"}
}
GTEOF

# 5. Launch GMAT
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

echo "=== Task Setup Complete: Debris manifest at ~/Desktop/debris_manifest.csv ==="
