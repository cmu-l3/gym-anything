#!/bin/bash
echo "=== Exporting compute_flood_hazard_index results ==="

source /workspace/scripts/task_utils.sh

# Paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
CSV_PATH="$RESULTS_DIR/flood_hazard_index.csv"
SUMMARY_PATH="$RESULTS_DIR/flood_hazard_summary.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output files existence and timestamps
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

SUMMARY_EXISTS="false"
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

# 3. Generate Ground Truth and Compare (Run Python inside container)
# We do this here because the container has h5py installed and the host might not.
# This script reads the HDF5, calculates the truth, reads the user CSV, and outputs a JSON comparison.

cat > /tmp/verify_internal.py << 'EOF'
import h5py
import numpy as np
import pandas as pd
import os
import json
import sys

muncie_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
csv_path = "/home/ga/Documents/hec_ras_results/flood_hazard_index.csv"

result = {
    "ground_truth_computed": False,
    "user_csv_valid": False,
    "accuracy": {
        "stations_matched": 0,
        "depth_mse": 999.9,
        "velocity_mse": 999.9,
        "dv_mse": 999.9,
        "category_accuracy": 0.0
    },
    "rows": []
}

# Find HDF file
hdf_file = None
for f in ["Muncie.p04.hdf", "Muncie.p04.tmp.hdf"]:
    p = os.path.join(muncie_dir, f)
    if os.path.exists(p):
        hdf_file = p
        break

if hdf_file:
    try:
        with h5py.File(hdf_file, 'r') as hf:
            # Path to XS output
            base = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections"
            
            # Load data
            flow = np.array(hf[f"{base}/Flow"])
            vel = np.array(hf[f"{base}/Velocity Channel"])
            
            # Determine depth
            if f"{base}/Hydraulic Depth" in hf:
                depth = np.array(hf[f"{base}/Hydraulic Depth"])
            else:
                wse = np.array(hf[f"{base}/Water Surface"])
                # Min channel elevation might be 1D or same shape
                # Simplified: assume WSE - Min Channel for now, or use hydraulic depth if available
                # Fallback: Just use WSE if depth missing (unlikely in 6.6)
                depth = np.zeros_like(wse) 

            # Get station names
            stations = [s.decode().strip() for s in hf[f"{base}/Station Names"][()]]
            
            # Find peak time index (global max flow)
            # Sum flow across all stations per timestep to find peak event time
            total_flow = np.sum(flow, axis=1)
            peak_idx = np.argmax(total_flow)
            
            # Extract values at peak
            ref_data = {}
            for i, st in enumerate(stations):
                d = float(depth[peak_idx, i])
                v = float(vel[peak_idx, i])
                dv = d * v
                
                cat = "Extreme"
                if dv < 4: cat = "Low"
                elif dv < 12: cat = "Medium"
                elif dv < 25: cat = "High"
                
                ref_data[st] = {
                    "depth": d,
                    "velocity": v,
                    "dv": dv,
                    "cat": cat
                }
            
            result["ground_truth_computed"] = True
            
            # Compare with User CSV
            if os.path.exists(csv_path):
                try:
                    df = pd.read_csv(csv_path)
                    # Normalize columns
                    df.columns = [c.lower().strip() for c in df.columns]
                    
                    # Check required columns
                    req = ['river_station', 'depth_ft', 'velocity_fps', 'dv_product', 'hazard_category']
                    if all(r in df.columns for r in req):
                        result["user_csv_valid"] = True
                        
                        matched = 0
                        depth_errs = []
                        vel_errs = []
                        dv_errs = []
                        cat_hits = 0
                        
                        for _, row in df.iterrows():
                            st = str(row['river_station']).strip()
                            if st in ref_data:
                                ref = ref_data[st]
                                matched += 1
                                depth_errs.append((float(row['depth_ft']) - ref['depth'])**2)
                                vel_errs.append((float(row['velocity_fps']) - ref['velocity'])**2)
                                dv_errs.append((float(row['dv_product']) - ref['dv'])**2)
                                
                                if str(row['hazard_category']).strip().lower() == ref['cat'].lower():
                                    cat_hits += 1
                        
                        if matched > 0:
                            result["accuracy"]["stations_matched"] = matched
                            result["accuracy"]["depth_mse"] = float(np.mean(depth_errs))
                            result["accuracy"]["velocity_mse"] = float(np.mean(vel_errs))
                            result["accuracy"]["dv_mse"] = float(np.mean(dv_errs))
                            result["accuracy"]["category_accuracy"] = float(cat_hits / matched)
                except Exception as e:
                    result["error_reading_csv"] = str(e)
                    
    except Exception as e:
        result["error_hdf"] = str(e)

print(json.dumps(result))
EOF

# Run the python script
PYTHON_RESULT=$(python3 /tmp/verify_internal.py 2>/dev/null || echo '{"error": "Python script failed"}')

# 4. Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during": $CSV_CREATED_DURING,
    "summary_exists": $SUMMARY_EXISTS,
    "internal_verification": $PYTHON_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"