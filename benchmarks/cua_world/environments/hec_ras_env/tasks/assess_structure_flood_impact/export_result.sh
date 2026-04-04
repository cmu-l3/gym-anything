#!/bin/bash
echo "=== Exporting assess_structure_flood_impact results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/hec_ras_results/structure_impact_assessment.csv"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"
INPUT_FILE="$MUNCIE_DIR/critical_infrastructure.csv"
GROUND_TRUTH_FILE="/tmp/ground_truth_impact.csv"

# 1. Generate Ground Truth using a hidden Python script
# This ensures we verify against the actual simulation data present in the environment
echo "Generating ground truth..."
cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import pandas as pd
import numpy as np
import sys

try:
    # Load HDF results
    hf = h5py.File(sys.argv[1], 'r')
    
    # Extract Max WSE
    # Path: Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
    # We need the max over time for each cross section
    wse_data = hf['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'][:]
    max_wse = np.max(wse_data, axis=0)
    
    # Get River Stations (need to map indices to station values)
    # The 2D flow area might complicate things, but Muncie is usually 1D XS
    # Path: Geometry/Cross Sections/River Stations
    stations_bytes = hf['Geometry/Cross Sections/River Stations'][:]
    stations = [float(s.decode('utf-8')) for s in stations_bytes]
    
    # Create reference dataframe
    df_ref = pd.DataFrame({'Station': stations, 'Max_WSE': max_wse})
    df_ref = df_ref.sort_values('Station', ascending=False) # River convention: high to low
    
    # Load Input CSV
    df_input = pd.read_csv(sys.argv[2])
    
    results = []
    
    for _, row in df_input.iterrows():
        fac_station = row['River_Station']
        ffe = row['FFE_ft']
        
        # Linear Interpolation
        # np.interp expects x to be increasing, so we flip if needed
        # But river stations decrease downstream.
        # Let's use numpy interp with sorted arrays
        
        x = df_ref['Station'].values
        y = df_ref['Max_WSE'].values
        
        # Sort by x ascending for np.interp
        sort_idx = np.argsort(x)
        x_sorted = x[sort_idx]
        y_sorted = y[sort_idx]
        
        interp_wse = np.interp(fac_station, x_sorted, y_sorted)
        
        flood_depth = interp_wse - ffe
        status = "FLOODED" if flood_depth > 0 else "SAFE"
        
        results.append({
            "Facility_Name": row['Facility_Name'],
            "River_Station": fac_station,
            "FFE_ft": ffe,
            "Interpolated_Max_WSE_ft": round(interp_wse, 2),
            "Flood_Depth_ft": round(flood_depth, 2),
            "Status": status
        })
        
    df_result = pd.DataFrame(results)
    df_result.to_csv(sys.argv[3], index=False)
    print("Ground truth generated successfully")

except Exception as e:
    print(f"Error generating ground truth: {e}")
    sys.exit(1)
PYEOF

# Run output generation if HDF exists
if [ -f "$HDF_FILE" ]; then
    python3 /tmp/generate_ground_truth.py "$HDF_FILE" "$INPUT_FILE" "$GROUND_TRUTH_FILE"
else
    echo "HDF file not found, cannot generate ground truth"
fi

# 2. Check Agent Output
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
ROW_COUNT=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Count rows (excluding header)
    ROW_COUNT=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare files for export (copy to /tmp for easy access by copy_from_env)
cp "$OUTPUT_FILE" /tmp/agent_output.csv 2>/dev/null || true
cp "$GROUND_TRUTH_FILE" /tmp/ground_truth.csv 2>/dev/null || true
chmod 666 /tmp/agent_output.csv /tmp/ground_truth.csv 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "row_count": $ROW_COUNT,
    "agent_file_path": "/tmp/agent_output.csv",
    "ground_truth_path": "/tmp/ground_truth.csv",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="