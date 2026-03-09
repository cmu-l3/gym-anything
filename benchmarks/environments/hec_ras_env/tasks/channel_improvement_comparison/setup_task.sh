#!/bin/bash
# setup_task.sh — channel_improvement_comparison
# Occupation: Environmental Engineer
# GT-in-Setup pattern:
#   1. Run baseline sim → capture baseline metrics as GT
#   2. Apply improvement (reduce main channel n by 25%) → run improved sim → GT
#   3. Reset model to baseline state for agent to start fresh
#   4. Create channel improvement spec document

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up channel_improvement_comparison task ==="

date +%s > /tmp/task_start_channelimp
TASK_START=$(cat /tmp/task_start_channelimp)

restore_muncie_project

mkdir -p "${RESULTS_DIR}"
rm -f "${RESULTS_DIR}/baseline_results.json"
rm -f "${RESULTS_DIR}/improved_results.json"
rm -f "${RESULTS_DIR}/scenario_comparison.csv"
rm -f "${RESULTS_DIR}/project_benefit_summary.txt"

TMP_HDF="${MUNCIE_DIR}/Muncie.p04.tmp.hdf"
OUT_HDF="${MUNCIE_DIR}/Muncie.p04.hdf"

# ----------------------------------------------------------------
# Step 1: Run baseline simulation with DEFAULT Manning's n
# ----------------------------------------------------------------
echo "Running BASELINE simulation to establish GT..."
cd "${MUNCIE_DIR}"
export LD_LIBRARY_PATH=/opt/hec-ras/lib:/opt/hec-ras/lib/mkl:/opt/hec-ras/lib/rhel_8:$LD_LIBRARY_PATH
RasUnsteady Muncie.p04.tmp.hdf x04 > /tmp/baseline_channelimp.log 2>&1 || true

python3 -u << 'PYEOF'
import h5py, numpy as np, json, os, shutil

muncie_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
tmp_hdf    = os.path.join(muncie_dir, "Muncie.p04.tmp.hdf")
out_hdf    = os.path.join(muncie_dir, "Muncie.p04.hdf")

ws_path    = ("Results/Unsteady/Output/Output Blocks/"
              "Base Output/Unsteady Time Series/2D Flow Areas/Muncie/Water Surface")
mn_path    = "Geometry/2D Flow Areas/Muncie/Manning's n"
elev_path  = "Geometry/2D Flow Areas/Muncie/Cells Minimum Elevation"

WSE_THRESHOLD = 930.0  # ft — inundation threshold

# Read baseline results
with h5py.File(out_hdf, "r") as f:
    ws = f[ws_path][:]

ws_f     = np.where(np.abs(ws) > 1e20, np.nan, ws.astype(float))
peak_wse = np.nanmax(ws_f)
mean_wse = float(np.nanmean(np.nanmax(ws_f, axis=0)))
n_cells  = ws_f.shape[1]
cell_peak_wse = np.nanmax(ws_f, axis=0)
n_inundated = int(np.sum(cell_peak_wse > WSE_THRESHOLD))

print(f"BASELINE: peak_wse={peak_wse:.3f} ft, mean_wse={mean_wse:.3f} ft, "
      f"inundated={n_inundated}/{n_cells}")

# Read baseline Manning's n
with h5py.File(tmp_hdf, "r") as f:
    mn_data   = f[mn_path][:]
    elev_data = f[elev_path][:]

mn_valid  = np.isfinite(mn_data)  & (mn_data > 0) & (mn_data < 1.0)
default_n = float(np.nanmean(mn_data[mn_valid]))
print(f"Default Manning's n: {default_n:.4f}")

# Step 2: Identify main-channel cells (lowest tercile of elevation)
elev_valid = elev_data[np.isfinite(elev_data)]
tercile_1  = np.percentile(elev_valid, 33.3)  # lowest tercile threshold
main_channel_mask = np.isfinite(elev_data) & (elev_data <= tercile_1)
n_main = int(np.sum(main_channel_mask))
print(f"Main channel cells (≤ {tercile_1:.1f} ft elevation): {n_main}/{len(elev_data)}")

# New Manning's n for improved conditions: reduce by 25%
improved_n = round(default_n * 0.75, 4)
print(f"Improved Manning's n (main channel): {improved_n:.4f} (25% reduction)")

# Step 3: Modify HDF5 with improved n
with h5py.File(tmp_hdf, "r+") as f:
    mn_arr = f[mn_path][:]
    mn_arr[main_channel_mask] = improved_n
    f[mn_path][:] = mn_arr
    print(f"Improved Manning's n applied to {n_main} main-channel cells")

# Step 4: Run improved simulation
import subprocess
result_imp = subprocess.run(
    ["RasUnsteady", "Muncie.p04.tmp.hdf", "x04"],
    capture_output=True, text=True, cwd=muncie_dir,
    env={**os.environ, "LD_LIBRARY_PATH":
         "/opt/hec-ras/lib:/opt/hec-ras/lib/mkl:/opt/hec-ras/lib/rhel_8"}
)
print("Improved simulation:", result_imp.returncode)

# Read improved results
with h5py.File(out_hdf, "r") as f:
    ws2 = f[ws_path][:]

ws2_f      = np.where(np.abs(ws2) > 1e20, np.nan, ws2.astype(float))
peak_wse2  = float(np.nanmax(ws2_f))
mean_wse2  = float(np.nanmean(np.nanmax(ws2_f, axis=0)))
cell_peak2 = np.nanmax(ws2_f, axis=0)
n_inund2   = int(np.sum(cell_peak2 > WSE_THRESHOLD))

print(f"IMPROVED: peak_wse={peak_wse2:.3f} ft, mean_wse={mean_wse2:.3f} ft, "
      f"inundated={n_inund2}/{n_cells}")

# Step 5: Save ground truth
gt = {
    "baseline_peak_wse":   round(peak_wse, 3),
    "baseline_mean_wse":   round(mean_wse, 3),
    "baseline_inundated":  n_inundated,
    "improved_peak_wse":   round(peak_wse2, 3),
    "improved_mean_wse":   round(mean_wse2, 3),
    "improved_inundated":  n_inund2,
    "total_cells":         n_cells,
    "wse_reduction_ft":    round(peak_wse - peak_wse2, 3),
    "flood_reduction_pct": round(100*(n_inundated - n_inund2)/n_inundated, 1) if n_inundated > 0 else 0,
    "default_n":           default_n,
    "improved_n":          improved_n,
    "tercile_threshold_ft": float(tercile_1),
    "wse_threshold_ft":    WSE_THRESHOLD,
    "design_criterion_ft": 0.3,
}
with open("/tmp/channelimp_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
print("GT saved:", json.dumps(gt, indent=2))

# Step 6: Reset HDF5 to BASELINE Manning's n (agent starts with original)
with h5py.File(tmp_hdf, "r+") as f:
    mn_arr = f[mn_path][:]
    mn_arr[mn_valid] = default_n
    f[mn_path][:] = mn_arr
print(f"HDF5 reset to baseline Manning's n = {default_n:.4f}")
PYEOF

# Write channel improvement specification
python3 -c "
import json
gt = json.load(open('/tmp/channelimp_gt.json'))
default_n  = gt['default_n']
improved_n = gt['improved_n']
pct_reduction = round((1 - improved_n/default_n)*100)
spec = f'''WHITE RIVER RESTORATION PROJECT — HYDRAULIC IMPROVEMENT SPECIFICATION
City of Muncie, Indiana — Indiana State Revolving Fund Application
Prepared by: Water Resources Engineering Division

PROJECT DESCRIPTION:
This project proposes selective channel improvements along the White River reach
modeled in the Muncie HEC-RAS project. Improvements include vegetation removal
from the main channel, bank stabilization with riprap, and selective dredging
of accumulated sediment at critical cross-sections.

HYDRAULIC DESIGN CRITERION:
The project must demonstrate a peak WSE reduction of at least 0.3 ft at the
downstream monitoring location to qualify for State Revolving Fund financing.

MANNING'S ROUGHNESS COEFFICIENT SPECIFICATION:
Existing conditions (baseline):      n = {default_n:.4f}  (current HDF5 model)
Proposed improved conditions:        n = {improved_n:.4f}  ({pct_reduction}% reduction)

The improved n value applies ONLY to main-channel cells (those with terrain
elevation in the lowest tercile of all computational cell elevations in the
2D flow domain). Floodplain cells retain their existing roughness values.

DELIVERABLES REQUIRED FOR SRF APPLICATION:
1. Baseline simulation results (JSON)
2. Improved conditions simulation results (JSON)
3. Scenario comparison table (CSV)
4. Technical benefit summary with design criterion assessment (TXT)

Reference: Indiana Clean Water Indiana Program, IDEM OWQ 2024
'''
open('/home/ga/Documents/channel_improvement_spec.txt', 'w').write(spec)
print('Channel improvement spec written.')
"

chown ga:ga /home/ga/Documents/channel_improvement_spec.txt

# Open terminal with context
echo "Opening terminal..."
launch_terminal "${MUNCIE_DIR}"
sleep 2

DISPLAY=:1 xdotool type --clearmodifiers --delay 20 \
    "echo '=== Channel Improvement Comparison Task ===' && cat ~/Documents/channel_improvement_spec.txt"
sleep 0.5
DISPLAY=:1 xdotool key --clearmodifiers Return
sleep 4

take_screenshot "/tmp/channelimp_task_start.png"
echo "=== channel_improvement_comparison setup complete ==="
exit 0
