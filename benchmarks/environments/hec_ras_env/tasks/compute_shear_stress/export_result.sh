#!/bin/bash
set -e
echo "=== Exporting compute_shear_stress result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
CSV_FILE="$RESULTS_DIR/shear_stress_analysis.csv"
SUMMARY_FILE="$RESULTS_DIR/shear_stress_summary.txt"
SCRIPT_FILE="$RESULTS_DIR/compute_shear_stress.py"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------
# PYTHON: Ground Truth Generation & Agent Output Parsing
# ---------------------------------------------------------
# We run this INSIDE the container to access h5py and the large HDF file directly.
# This generates a JSON with both the Ground Truth values and the Agent's values.

PYTHON_EXPORT_SCRIPT=$(mktemp)
cat > "$PYTHON_EXPORT_SCRIPT" << 'PYEOF'
import h5py
import numpy as np
import os
import csv
import json
import glob

results = {
    "ground_truth": {},
    "agent_data": {},
    "files": {}
}

muncie_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
csv_file = "/home/ga/Documents/hec_ras_results/shear_stress_analysis.csv"
summary_file = "/home/ga/Documents/hec_ras_results/shear_stress_summary.txt"
script_file = "/home/ga/Documents/hec_ras_results/compute_shear_stress.py"

# --- 1. File Existence & Metadata ---
def get_file_info(path):
    if os.path.exists(path):
        stat = os.stat(path)
        return {
            "exists": True,
            "size": stat.st_size,
            "mtime": stat.st_mtime
        }
    return {"exists": False, "size": 0, "mtime": 0}

results["files"]["csv"] = get_file_info(csv_file)
results["files"]["summary"] = get_file_info(summary_file)
results["files"]["script"] = get_file_info(script_file)

# Find the HDF file (could be .p04.hdf or .p04.tmp.hdf)
hdf_files = glob.glob(os.path.join(muncie_dir, "*.p04*.hdf"))
hdf_path = hdf_files[0] if hdf_files else None
results["files"]["hdf"] = get_file_info(hdf_path) if hdf_path else {"exists": False}

# --- 2. Ground Truth Computation ---
try:
    if hdf_path and os.path.exists(hdf_path):
        with h5py.File(hdf_path, 'r') as f:
            # Locate Cross Sections group
            # Path can vary slightly; try standard unsteady paths
            base_paths = [
                "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections",
                "Results/Unsteady/Output/Output Blocks/DSS Profile Output/Unsteady Time Series/Cross Sections"
            ]
            xs_group = None
            for p in base_paths:
                if p in f:
                    xs_group = f[p]
                    break
            
            if xs_group:
                # Get River Stations
                stations = []
                if "River Stations" in xs_group:
                    stations = [s.decode().strip() for s in xs_group["River Stations"][:]]
                elif "Station" in xs_group: # Depending on HDF version
                    stations = [s.decode().strip() for s in xs_group["Station"][:]]
                elif "Attributes" in xs_group:
                     # Fallback for some RAS versions
                     pass
                
                # Get Data arrays
                # Need: Flow (to find peak time), Velocity, Hydraulic Radius
                flow = xs_group["Flow"][:] if "Flow" in xs_group else None
                velocity = xs_group["Velocity Channel"][:] if "Velocity Channel" in xs_group else xs_group.get("Velocity Total")[:]
                hyd_radius = xs_group["Hydraulic Radius"][:] if "Hydraulic Radius" in xs_group else None

                if flow is not None and velocity is not None:
                    # Find peak flow index (sum of flow across all XS for each time step)
                    # Simple approach: Max flow at a representative station or max total flow
                    # Let's use max total flow at the middle station to determine "system peak"
                    # Or just max flow sum across all stations
                    total_flow_per_step = np.sum(np.abs(flow), axis=1)
                    peak_idx = np.argmax(total_flow_per_step)
                    
                    gt_shear = {}
                    gamma = 62.4
                    n = 0.035
                    kn = 1.486
                    conversion = 47.88

                    count = 0
                    for i, station in enumerate(stations):
                        v = abs(velocity[peak_idx, i])
                        r = abs(hyd_radius[peak_idx, i]) if hyd_radius is not None else 1.0 # Avoid div/0 if missing
                        
                        if r > 1e-4:
                            tau_imperial = (gamma * (n**2) * (v**2)) / ((kn**2) * (r**(1/3)))
                            tau_pa = tau_imperial * conversion
                        else:
                            tau_pa = 0.0
                        
                        gt_shear[station] = float(tau_pa)
                        count += 1
                    
                    # Calculate stats
                    vals = list(gt_shear.values())
                    max_station = max(gt_shear, key=gt_shear.get) if vals else ""
                    max_val = gt_shear[max_station] if vals else 0
                    mean_val = float(np.mean(vals)) if vals else 0
                    
                    results["ground_truth"] = {
                        "peak_time_index": int(peak_idx),
                        "count": count,
                        "max_station": max_station,
                        "max_value_pa": max_val,
                        "mean_value_pa": mean_val,
                        "sample_values": {k: gt_shear[k] for k in list(gt_shear.keys())[:5]} # Sample for debug
                    }
                    
                    # Store full map for verifying agent's CSV
                    results["ground_truth"]["full_map"] = gt_shear

except Exception as e:
    results["ground_truth_error"] = str(e)

# --- 3. Agent Output Parsing ---
try:
    if os.path.exists(csv_file):
        agent_data = {}
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers
            headers = [h.strip().lower() for h in reader.fieldnames] if reader.fieldnames else []
            
            # Identify columns
            station_col = next((h for h in reader.fieldnames if "station" in h.lower()), None)
            shear_col = next((h for h in reader.fieldnames if "shear" in h.lower() or "pa" in h.lower()), None)
            
            if station_col and shear_col:
                for row in reader:
                    try:
                        s = row[station_col].strip()
                        v = float(row[shear_col])
                        agent_data[s] = v
                    except:
                        pass
        
        vals = list(agent_data.values())
        results["agent_data"] = {
            "count": len(agent_data),
            "max_station": max(agent_data, key=agent_data.get) if vals else "",
            "max_value_pa": max(vals) if vals else 0,
            "mean_value_pa": float(np.mean(vals)) if vals else 0,
            "full_map": agent_data
        }

    if os.path.exists(summary_file):
        with open(summary_file, 'r') as f:
            results["agent_summary_content"] = f.read()

except Exception as e:
    results["agent_data_error"] = str(e)

print(json.dumps(results))
PYEOF

# Run the python script and capture output to JSON
python3 "$PYTHON_EXPORT_SCRIPT" > /tmp/task_result.json 2>/dev/null || echo '{"error": "Export script failed"}' > /tmp/task_result.json

# Cleanup
rm -f "$PYTHON_EXPORT_SCRIPT"

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="