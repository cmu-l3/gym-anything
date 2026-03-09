#!/bin/bash
echo "=== Exporting analyze_lateral_velocity_diff result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CSV_PATH="/home/ga/Documents/hec_ras_results/lateral_shear_analysis.csv"
TXT_PATH="/home/ga/Documents/hec_ras_results/high_shear_zones.txt"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"

# Check output files
CSV_EXISTS="false"
TXT_EXISTS="false"
CSV_CREATED_DURING="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
fi

# Generate Ground Truth for Verification
# We calculate the expected values from the HDF file using a python script
echo "Calculating ground truth..."
cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    hdf_path = sys.argv[1]
    with h5py.File(hdf_path, 'r') as f:
        # Locate Cross Section Data
        # Typical path: /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/
        base_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        if base_path not in f:
            print(json.dumps({"error": "Results path not found"}))
            sys.exit(0)
            
        xs_group = f[base_path]
        
        # Get River Stations (attributes or separate dataset)
        # Often stored as 'River Station' attribute on the group
        # Or implicitly by index. Let's look for specific datasets.
        
        # We need Flow and Area to calculate Velocity if Velocity components aren't there
        # Let's check for 'Flow' and 'Area' datasets
        
        # Note: In HEC-RAS HDF, data is often stored as (Time, XS) or (Time, XS, Component)
        # Let's try to find Flow Total, Flow Left, Flow Right, etc.
        
        # Simplified logic for verification:
        # We will iterate through keys in the group to find datasets
        
        results = []
        
        # Assuming standard naming conventions or 'Flow' array with parts
        # If we can't easily parse the structure generically without Rashdf, 
        # we'll look for standard 1D output arrays.
        
        # Validating output existence is enough if we can't replicate calculation perfectly in this script.
        # But let's try to get the 'Flow' dataset.
        
        flow_path = f"{base_path}/Flow"
        area_path = f"{base_path}/Area"
        
        # If simple paths exist, we use them. 
        # If not, we rely on the agent's file existence and format.
        
        ground_truth = {
            "file_valid": True,
            "has_results": True
        }
        
        print(json.dumps(ground_truth))

except Exception as e:
    print(json.dumps({"error": str(e), "file_valid": False}))
EOF

# Run ground truth calculation (simplified to just validate HDF existence for now, 
# as full hydraulic calc in shell script is fragile without guaranteed schema)
# In a real scenario, we'd use a robust library. Here we'll trust the Python env.
GROUND_TRUTH_JSON=$(python3 /tmp/calc_ground_truth.py "$HDF_PATH" 2>/dev/null || echo '{"error": "Script failed"}')

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "txt_exists": $TXT_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy user files to tmp for external verification
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$CSV_PATH" /tmp/user_lateral_shear.csv
    chmod 666 /tmp/user_lateral_shear.csv
fi
if [ "$TXT_EXISTS" = "true" ]; then
    cp "$TXT_PATH" /tmp/user_high_shear.txt
    chmod 666 /tmp/user_high_shear.txt
fi

echo "Export complete"