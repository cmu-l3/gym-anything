#!/bin/bash
# setup_task.sh — flood_frequency_analysis
# Occupation: Civil Engineer / Hydraulic Engineer
# Sets up USGS frequency data, clean Muncie project, results directory

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up flood_frequency_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_flood_freq
TASK_START=$(cat /tmp/task_start_flood_freq)

# Restore a clean copy of the Muncie project
restore_muncie_project

# Make sure results directory exists and is clean
mkdir -p "${RESULTS_DIR}"
rm -f "${RESULTS_DIR}/frequency_results.csv"
rm -f "${RESULTS_DIR}/bfe_documentation.txt"
rm -f "${RESULTS_DIR}/peak_wse_10yr.txt"
rm -f "${RESULTS_DIR}/peak_wse_50yr.txt"
rm -f "${RESULTS_DIR}/peak_wse_100yr.txt"

# ----------------------------------------------------------------
# Write USGS flood frequency report (real StreamStats values for
# USGS Gauge 03349000, White River at Muncie, IN)
# Source: USGS StreamStats, Indiana, retrieved 2024
# ----------------------------------------------------------------
cat > /home/ga/Documents/usgs_white_river_frequency.txt << 'FREQEOF'
USGS PEAK-FLOW FREQUENCY ANALYSIS
White River at Muncie, Indiana
USGS Streamgage 03349000
Drainage Area: 3,884 square miles
Period of Record: 1927–2023 (77 years)
Method: Bulletin 17C Log-Pearson Type III

Peak-Flow Frequency Estimates:
  Return Period    Annual Exceedance    Design Peak Flow
  (years)          Probability (%)      (cfs)
  -------------------------------------------------------
  10               10.0                 16200
  50                2.0                 23100
  100               1.0                 26200

Notes:
- Flows represent natural streamflow conditions at gauge location.
- Values are used for planning-level analysis only.
- For regulatory use, contact USGS Indiana Water Science Center.
- Reference: USGS StreamStats Indiana, https://streamstats.usgs.gov/
FREQEOF

chown ga:ga /home/ga/Documents/usgs_white_river_frequency.txt

# ----------------------------------------------------------------
# Verify the b04 boundary file exists and identify baseline peak flow
# ----------------------------------------------------------------
B04_FILE="${MUNCIE_DIR}/Muncie.b04"
if [ ! -f "$B04_FILE" ]; then
    echo "ERROR: Muncie.b04 not found at $B04_FILE"
    exit 1
fi

BASELINE_PEAK=$(grep -oE '[0-9]+\.' "${B04_FILE}" | sort -n | tail -1 | tr -d '.' || echo "21000")
echo "Baseline peak flow detected: ~${BASELINE_PEAK} cfs"

# Save ground-truth context for verifier (the allowed WSE range from known model behavior)
# These ranges are conservative bounds — the actual values depend on the simulation
python3 << 'PYEOF'
import json

# From evidence_docs: Muncie model with 21000 cfs peak gives:
#   Overall peak WSE ~953.84 ft, Mean peak WSE ~946.10 ft
# Scaling relationships (approximate linear for small perturbations):
#   Q_10 = 16200 cfs  => ratio 0.771 => WSE slightly lower
#   Q_50 = 23100 cfs  => ratio 1.100 => WSE slightly higher
#   Q_100 = 26200 cfs => ratio 1.248 => WSE higher still
# We use conservative plausibility bounds:
gt = {
    "baseline_peak_cfs": 21000,
    "design_flows": {
        "10": 16200,
        "50": 23100,
        "100": 26200
    },
    "wse_plausibility_min_ft": 935.0,
    "wse_plausibility_max_ft": 965.0,
    "task_desc": "Flood frequency analysis — 3 return periods"
}
with open("/tmp/flood_freq_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
print("Ground truth context saved to /tmp/flood_freq_gt.json")
PYEOF

# ----------------------------------------------------------------
# Open a terminal in the Muncie project directory
# ----------------------------------------------------------------
echo "Opening terminal in Muncie project directory..."
launch_terminal "${MUNCIE_DIR}"
sleep 2

# Display helpful context in the terminal
DISPLAY=:1 xdotool type --clearmodifiers --delay 20 \
    "echo '=== Flood Frequency Analysis Task ===' && ls -la && echo '--- Frequency Report ---' && cat ~/Documents/usgs_white_river_frequency.txt"
sleep 0.5
DISPLAY=:1 xdotool key --clearmodifiers Return
sleep 3

take_screenshot "/tmp/flood_freq_task_start.png"

echo "=== flood_frequency_analysis setup complete ==="
exit 0
