#!/bin/bash
# setup_task.sh — dam_breach_scenario
# Occupation: Civil Engineer / Dam Safety Engineer
# Creates dam breach parameters document; restores clean Muncie project.
# The dam breach peak outflow (45,000 cfs) is significantly larger than the
# existing 21,000 cfs design storm — requiring hydrograph reconstruction.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up dam_breach_scenario task ==="

date +%s > /tmp/task_start_dambreach
TASK_START=$(cat /tmp/task_start_dambreach)

restore_muncie_project

mkdir -p "${RESULTS_DIR}"
rm -f "${RESULTS_DIR}/dam_breach_report.txt"

B04_FILE="${MUNCIE_DIR}/Muncie.b04"

# ----------------------------------------------------------------
# Record baseline state for verifier
# ----------------------------------------------------------------
ORIGINAL_B04_LINES=$(wc -l < "$B04_FILE")
echo "Original b04 lines: $ORIGINAL_B04_LINES"
python3 -c "
import json
gt = {
    'peak_breach_flow_cfs': 45000,
    'time_to_peak_hr': 2,
    'base_duration_hr': 12,
    'original_b04_lines': $ORIGINAL_B04_LINES,
    # Plausibility bounds for the dam-breach simulation
    # Peak must be HIGHER than the standard flood (21000 cfs baseline gives ~953.84 ft)
    'expected_peak_wse_min': 954.0,
    'expected_peak_wse_max': 975.0,
    'task_desc': 'Dam breach scenario — 45000 cfs peak breach outflow'
}
with open('/tmp/dambreach_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print('GT saved:', gt)
"

# ----------------------------------------------------------------
# Write dam breach parameters document (realistic Froehlich 1995
# parameters for a hypothetical earthen dam upstream of Muncie).
# Source: Froehlich (1995) Peak Outflow from Breached Embankment Dam
# ASCE Journal of Water Resources Planning and Management
# ----------------------------------------------------------------
cat > /home/ga/Documents/dam_breach_parameters.txt << 'DAMEOF'
INDIANA DAM SAFETY PROGRAM — HYPOTHETICAL BREACH ANALYSIS
Upstream Dam: Reservoir Creek Embankment Dam
Location: ~12 miles upstream of USGS Gauge 03349000, Muncie, IN
Dam Type: Earthen embankment
Dam Height: 42 feet (above streambed)
Reservoir Volume: 8,400 acre-feet (at full pool)

BREACH PARAMETERS (Froehlich 1995 Peak Outflow Method):
Reference: Froehlich, D.C. (1995). Peak Outflow from Breached Embankment Dam.
           J. Water Resour. Plng. and Mgmt., ASCE, 121(1), 90-97.
           Equation: Qp = 0.272 * Kₒ * Vw^0.5 * hw^1.25

Computed Breach Outflow Hydrograph Parameters:
  Peak Breach Outflow:   45000 cfs
  Time to Peak (Tp):     2 hours  (from breach initiation to peak outflow)
  Total Base Duration:   12 hours (from breach initiation to negligible outflow)

Hydrograph Shape: Triangular approximation
  - Flow rises linearly from 0 to 45000 cfs over first 2 hours
  - Flow recedes linearly from 45000 cfs back to 0 over remaining 10 hours

NOTE: Use 1-hour time steps when constructing the input hydrograph.
Convert hours to minutes for the HEC-RAS b04 boundary condition file
(Interval=1MIN requires time in minutes on each data line).

This analysis is for emergency planning purposes only.
DAMEOF

chown ga:ga /home/ga/Documents/dam_breach_parameters.txt

# ----------------------------------------------------------------
# Also back up the original b04 so the agent can inspect it
# ----------------------------------------------------------------
cp "${B04_FILE}" "${MUNCIE_DIR}/Muncie.b04.original_backup"

# Open terminal
echo "Opening terminal..."
launch_terminal "${MUNCIE_DIR}"
sleep 2

DISPLAY=:1 xdotool type --clearmodifiers --delay 20 \
    "echo '=== Dam Breach Scenario ===' && cat ~/Documents/dam_breach_parameters.txt && echo '' && echo '--- Current b04 boundary file ---' && head -30 Muncie.b04"
sleep 0.5
DISPLAY=:1 xdotool key --clearmodifiers Return
sleep 4

take_screenshot "/tmp/dambreach_task_start.png"
echo "=== dam_breach_scenario setup complete ==="
exit 0
