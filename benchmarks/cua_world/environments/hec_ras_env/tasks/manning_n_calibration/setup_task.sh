#!/bin/bash
# setup_task.sh — manning_n_calibration
# Occupation: Senior Hydrologist
# GT-in-Setup pattern:
#   1. Capture default Manning's n from the HDF5
#   2. Run baseline simulation → record peak WSE as "observed" target
#   3. Perturb Manning's n in the HDF5 (increase it to make model over-predict)
#   4. Save GT so verifier knows the target and original n
#   5. Present the agent with the perturbed model + observed gauge data

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up manning_n_calibration task ==="

date +%s > /tmp/task_start_calib
TASK_START=$(cat /tmp/task_start_calib)

# Start with clean Muncie project
restore_muncie_project

mkdir -p "${RESULTS_DIR}"
rm -f "${RESULTS_DIR}/calibration_log.csv"
rm -f "${RESULTS_DIR}/calibration_report.txt"

TMP_HDF="${MUNCIE_DIR}/Muncie.p04.tmp.hdf"
OUT_HDF="${MUNCIE_DIR}/Muncie.p04.hdf"

# ----------------------------------------------------------------
# GT-in-Setup Step 1: Run a baseline simulation with DEFAULT n
# to get the "true" model peak WSE that we'll call the "observed" target
# ----------------------------------------------------------------
echo "Running baseline simulation with default Manning's n to establish target..."
cd "${MUNCIE_DIR}"
export LD_LIBRARY_PATH=/opt/hec-ras/lib:/opt/hec-ras/lib/mkl:/opt/hec-ras/lib/rhel_8:$LD_LIBRARY_PATH
RasUnsteady Muncie.p04.tmp.hdf x04 > /tmp/baseline_sim.log 2>&1 || true

python3 -u << 'PYEOF'
import h5py, numpy as np, json, os, shutil

muncie_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
tmp_hdf    = os.path.join(muncie_dir, "Muncie.p04.tmp.hdf")
out_hdf    = os.path.join(muncie_dir, "Muncie.p04.hdf")

ws_path  = ("Results/Unsteady/Output/Output Blocks/"
            "Base Output/Unsteady Time Series/2D Flow Areas/Muncie/Water Surface")
mn_path  = "Geometry/2D Flow Areas/Muncie/Manning's n"
elev_path = "Geometry/2D Flow Areas/Muncie/Cells Minimum Elevation"

# Step 1: Read baseline Manning's n and peak WSE
with h5py.File(out_hdf, "r") as f:
    ws   = f[ws_path][:]
    ws_f = np.where(np.abs(ws) > 1e20, np.nan, ws.astype(float))
    baseline_peak_wse = float(np.nanmax(ws_f))
    print(f"Baseline peak WSE (default n): {baseline_peak_wse:.3f} ft")

with h5py.File(tmp_hdf, "r") as f:
    mn_data      = f[mn_path][:]
    elev_data    = f[elev_path][:]
    default_n    = float(np.nanmean(mn_data[np.isfinite(mn_data)]))
    print(f"Default Manning's n (mean): {default_n:.4f}")

# Step 2: Choose a "wrong" Manning's n to give to the agent
# We increase n so the model over-predicts (higher WSE), and the agent
# must lower it back toward the "observed" target.
# Increase n by ~20% to create a clear calibration signal
wrong_n = round(default_n * 1.20, 4)

# Step 3: Write perturbed Manning's n into the template HDF5
with h5py.File(tmp_hdf, "r+") as f:
    mn_array = f[mn_path][:]
    mn_finite = np.isfinite(mn_array) & (mn_array > 0) & (mn_array < 1.0)
    mn_array[mn_finite] = wrong_n
    f[mn_path][:] = mn_array
    print(f"Perturbed Manning's n written: {wrong_n:.4f} (was ~{default_n:.4f})")

# Step 4: Save ground truth
gt = {
    "true_default_n":       round(default_n, 4),
    "wrong_n_given":        wrong_n,
    "observed_peak_wse_ft": round(baseline_peak_wse, 3),
    "acceptable_residual_ft": 0.5,
    "task_desc": "Calibrate Manning's n to reproduce baseline peak WSE"
}
with open("/tmp/calib_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
print(f"GT saved: target peak WSE = {baseline_peak_wse:.3f} ft, correct n ≈ {default_n:.4f}")

# Step 5: Write observed gauge data for the agent
observed_doc = f"""USGS STREAM GAUGE OBSERVATION REPORT
White River at Muncie, Indiana — USGS Gauge 03349000
Storm Event: Model Calibration Storm (24-hour event)

Observed Peak Water Surface Elevation: {baseline_peak_wse:.2f} ft (NAVD 88)
Observation Date: See project records
Gauge Rating: Indirect measurement, ±0.3 ft uncertainty

This value represents the peak stage recorded at the downstream
end of the modeled reach during the calibration storm event.
The HEC-RAS model must be adjusted to reproduce this observed
peak WSE within ±0.5 ft calibration tolerance.

Reference: USGS National Water Information System (NWIS)
           https://waterdata.usgs.gov/in/nwis/peak
"""
with open("/home/ga/Documents/observed_gauge_data.txt", "w") as f:
    f.write(observed_doc)
print("Observed gauge data written to ~/Documents/observed_gauge_data.txt")
PYEOF

chown ga:ga /home/ga/Documents/observed_gauge_data.txt

# Open terminal in Muncie directory
echo "Opening terminal..."
launch_terminal "${MUNCIE_DIR}"
sleep 2

DISPLAY=:1 xdotool type --clearmodifiers --delay 20 \
    "echo '=== Manning n Calibration Task ===' && cat ~/Documents/observed_gauge_data.txt && echo '' && python3 -c \"import h5py,numpy as np; f=h5py.File('Muncie.p04.tmp.hdf','r'); n=f[\\\"Geometry/2D Flow Areas/Muncie/Manning\'s n\\\"][:]; print('Current mean Manning n:', round(float(np.nanmean(n[n>0])),4))\""
sleep 0.5
DISPLAY=:1 xdotool key --clearmodifiers Return
sleep 4

take_screenshot "/tmp/calib_task_start.png"
echo "=== manning_n_calibration setup complete ==="
exit 0
