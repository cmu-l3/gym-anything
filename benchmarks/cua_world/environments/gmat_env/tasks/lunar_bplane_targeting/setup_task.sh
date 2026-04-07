#!/bin/bash
set -euo pipefail

echo "=== Setting up lunar_bplane_targeting task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/lunascout_tli_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create the mission specification document
cat > /home/ga/Desktop/lunascout_tli_spec.txt << 'SPECEOF'
================================================================
MISSION ANALYSIS DIRECTIVE: LunaScout-1
Phase: Translunar Injection (TLI) Targeting
================================================================

SPACECRAFT: LunaScout-1
Mass: 25.0 kg
DragArea: 0.1 m^2
Cr: 1.5

PARKING ORBIT STATE (Frame: EarthMJ2000Eq):
Epoch: 22 Jul 2014 11:29:10.811 UTCG
State Type: Cartesian
X  = -137.380191 km
Y  = 5934.303107 km
Z  = 3058.422785 km
VX = -7.347716 km/s
VY = -0.668551 km/s
VZ =  1.096056 km/s

MANEUVER CONSTRAINTS:
Frame: VNB (Velocity-Normal-Binormal)
Initial Guess: V = 3.123 km/s, N = 0.0 km/s, B = 0.0 km/s
Variables to Vary: V-direction and N-direction components.
(Leave B-direction fixed at 0.0).

TARGET CONDITIONS:
Target Body: Luna (Moon)
Coordinate System: Moon-centered, EarthMJ2000Eq axes (e.g., MoonInertial)
Target BdotT: 3500.0 km
Target BdotR: -2000.0 km

OUTPUT REQUIREMENTS:
Report File: ~/GMAT_output/lunascout_tli_report.txt
The report MUST contain EXACTLY these lines (replace <value> with your final numbers):
Converged_Burn_V_kmps: <value>
Converged_Burn_N_kmps: <value>
Achieved_BdotT_km: <value>
Achieved_BdotR_km: <value>
================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/lunascout_tli_spec.txt

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