#!/bin/bash
echo "=== Exporting identify_overbank_flow results ==="

source /workspace/scripts/task_utils.sh

# Paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output files
SCRIPT_PATH="$RESULTS_DIR/overbank_analysis.py"
CSV_PATH="$RESULTS_DIR/overbank_analysis.csv"
SUMMARY_PATH="$RESULTS_DIR/overbank_summary.txt"

SCRIPT_EXISTS="false"
CSV_EXISTS="false"
SUMMARY_EXISTS="false"
SCRIPT_NEW="false"
CSV_NEW="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if [ $(stat -c %Y "$SCRIPT_PATH") -gt "$TASK_START" ]; then SCRIPT_NEW="true"; fi
fi

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    if [ $(stat -c %Y "$CSV_PATH") -gt "$TASK_START" ]; then CSV_NEW="true"; fi
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

# 3. Generate Ground Truth (Calculated inside container to ensure environment match)
# We run a python script to calculate the correct values from the HDF file
echo "Generating ground truth..."

cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import pandas as pd
import sys
import json

try:
    f = h5py.File(sys.argv[1], 'r')
    
    # 1. Get River Stations
    # HDF path for 2D unsteady often has 1D XS under Geometry/Cross Sections
    # Adjust paths based on HEC-RAS HDF5 schema (v6.x)
    
    base_geom = 'Geometry/Cross Sections'
    base_res = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
    
    # Get RS names
    rs_names = [x.decode('utf-8') for x in f[f'{base_geom}/Attributes']['River Station'][:]]
    
    results = []
    
    for i, rs in enumerate(rs_names):
        # 2. Get Bank info
        # Bank Stations are usually stored in 'Bank Stations' dataset or need to be looked up
        # In simple 1D, they are often in attributes or a separate table.
        # For this verification, we'll try to look them up. 
        # Note: If complex lookup is needed, we approximate for verification or verify the logic.
        
        # Access Station-Elevation data (Coord-Elev)
        # In HDF, this is often a jagged array or indexed.
        # Structure: Geometry/Cross Sections/Coordinate-Elevation
        # If simplistic extraction fails, we might just verify the WSE extraction.
        
        # Let's try to extract Bank Stations directly if available
        bank_stations = f[f'{base_geom}/Bank Stations'][i] # [Left, Right]
        
        # Get coordinates to lookup elevation
        # Start/Count index for this XS
        info_idx = f[f'{base_geom}/Station Elevation Info'][i] # [Start, Count]
        start = info_idx[0]
        count = info_idx[1]
        
        coords = f[f'{base_geom}/Station Elevation Data'][start:start+count] # [Station, Elev]
        
        # Lookup elevations
        # Simple interpolation or nearest match
        def get_elev(station, points):
            # points is Nx2
            sts = points[:,0]
            els = points[:,1]
            return np.interp(station, sts, els)
            
        left_bank_elev = get_elev(bank_stations[0], coords)
        right_bank_elev = get_elev(bank_stations[1], coords)
        min_bank = min(left_bank_elev, right_bank_elev)
        
        # 3. Get WSE Results
        # Shape: [Time, CrossSection] or similar
        # Path: Results/.../Water Surface
        # Usually checking the dataset shape.
        
        wse_data = f[f'{base_res}/Water Surface'][:, i]
        max_wse = np.max(wse_data)
        
        # 4. Logic
        overtopped = max_wse > min_bank
        depth = max_wse - min_bank if overtopped else 0.0
        
        # Find first index
        first_idx = -1
        if overtopped:
            idx_list = np.where(wse_data > min_bank)[0]
            if len(idx_list) > 0:
                first_idx = int(idx_list[0])
                
        results.append({
            "River_Station": rs,
            "Min_Bank_Elev_ft": float(min_bank),
            "Max_WSE_ft": float(max_wse),
            "Overtopped": "Yes" if overtopped else "No",
            "First_Overtop_Index": first_idx,
            "Max_Overtop_Depth_ft": float(depth)
        })
        
    f.close()
    
    # Calculate summary
    df = pd.DataFrame(results)
    summary = {
        "total_xs": len(df),
        "overtopped_count": len(df[df['Overtopped'] == 'Yes']),
        "non_overtopped_count": len(df[df['Overtopped'] == 'No']),
        "max_depth": float(df['Max_Overtop_Depth_ft'].max()),
        "max_depth_rs": df.loc[df['Max_Overtop_Depth_ft'].idxmax()]['River_Station']
    }
    
    output = {
        "rows": results,
        "summary": summary,
        "success": True
    }
    
    print(json.dumps(output))
    
except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))

EOF

# Run generator using container python
GROUND_TRUTH_JSON=$(python3 /tmp/generate_ground_truth.py "$HDF_FILE")

# 4. Prepare JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Read agent csv content if exists
AGENT_CSV_CONTENT=""
if [ "$CSV_EXISTS" = "true" ]; then
    AGENT_CSV_CONTENT=$(cat "$CSV_PATH" | head -n 50 | base64 -w 0) # Encode first 50 lines to avoid JSON break
fi

# Read agent summary content
AGENT_SUMMARY_CONTENT=""
if [ "$SUMMARY_EXISTS" = "true" ]; then
    AGENT_SUMMARY_CONTENT=$(cat "$SUMMARY_PATH" | base64 -w 0)
fi

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_new": $SCRIPT_NEW,
    "csv_exists": $CSV_EXISTS,
    "csv_new": $CSV_NEW,
    "summary_exists": $SUMMARY_EXISTS,
    "ground_truth": $GROUND_TRUTH_JSON,
    "agent_csv_b64": "$AGENT_CSV_CONTENT",
    "agent_summary_b64": "$AGENT_SUMMARY_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"