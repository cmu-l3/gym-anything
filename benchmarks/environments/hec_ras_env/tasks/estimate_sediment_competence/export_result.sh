#!/bin/bash
echo "=== Exporting estimate_sediment_competence results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define Output Paths
CSV_PATH="/home/ga/Documents/hec_ras_results/sediment_competence.csv"
SUMMARY_PATH="/home/ga/Documents/hec_ras_results/competence_summary.txt"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"
if [ ! -f "$HDF_FILE" ]; then
    HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"
fi

# 3. Check Agent Outputs
CSV_EXISTS="false"
SUMMARY_EXISTS="false"
CSV_SIZE=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

# 4. Generate Ground Truth Data (Internal Python Script)
# We run this INSIDE the container to extract true shear stresses from the HDF file
# so the verifier (on host) can compare against them.
echo "Generating ground truth data..."

cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import os
import sys

hdf_path = sys.argv[1]
output_path = "/tmp/ground_truth.json"

try:
    if not os.path.exists(hdf_path):
        print(json.dumps({"error": "HDF file not found"}))
        sys.exit(0)

    with h5py.File(hdf_path, 'r') as f:
        # Navigate to Unsteady results
        # Path structure typically: /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/
        base_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections"
        
        if base_path not in f:
            print(json.dumps({"error": f"Path {base_path} not found in HDF"}))
            sys.exit(0)
            
        xs_group = f[base_path]
        
        # Get River Stations (names of subgroups usually, or stored in attributes)
        # In RAS HDF, Cross Sections are groups named by River Station or index.
        # Often there is a geometry mapping. 
        # For simplicity in this env, we iterate keys in the Cross Sections group.
        
        # Note: RAS 6.x HDF structure can vary. We assume standard 2D/1D Unsteady structure.
        # Let's try to find "Shear Channel" or "Shear Stress" dataset.
        
        ground_truth = {}
        
        # We need the time of peak flow. 
        # Usually easier to find max shear across all time steps for each XS, 
        # assuming peak shear ~ peak flow.
        # Or find the index of max flow at a reference station.
        
        # Let's extract max shear for each station found.
        # Keys in xs_group are usually 'River Station' strings.
        
        for rs_name in xs_group.keys():
            rs_data = xs_group[rs_name]
            
            # Look for Shear Stress dataset
            shear_ds_name = None
            for key in rs_data.keys():
                if "Shear" in key and "Channel" in key:
                    shear_ds_name = key
                    break
            
            if not shear_ds_name:
                # Fallback to just "Shear Stress" if channel specific not found
                for key in rs_data.keys():
                    if "Shear Stress" in key:
                        shear_ds_name = key
                        break
            
            if shear_ds_name:
                data = rs_data[shear_ds_name][()]
                # data is time series. We want value at peak.
                # Simplification for verification: Use MAX value. 
                # The task asks for "at time of peak flow". 
                # In river hydraulics, peak shear usually coincides with peak flow.
                max_shear = float(np.max(data))
                ground_truth[rs_name] = max_shear
        
        with open(output_path, 'w') as out:
            json.dump({"shear_data": ground_truth}, out)
            
except Exception as e:
    with open(output_path, 'w') as out:
        json.dump({"error": str(e)}, out)
EOF

python3 /tmp/generate_ground_truth.py "$HDF_FILE"

# 5. Prepare results for export
# Copy agent files to /tmp for easy extraction
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$CSV_PATH" /tmp/agent_sediment.csv
fi
if [ "$SUMMARY_EXISTS" = "true" ]; then
    cp "$SUMMARY_PATH" /tmp/agent_summary.txt
fi

# 6. Create Meta-Result JSON
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "summary_exists": $SUMMARY_EXISTS,
    "csv_size": $CSV_SIZE,
    "timestamp": "$(date +%s)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json /tmp/ground_truth.json /tmp/agent_sediment.csv /tmp/agent_summary.txt 2>/dev/null || true

echo "=== Export complete ==="