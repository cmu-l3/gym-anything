#!/bin/bash
echo "=== Exporting compute_flood_arrival_time results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_PATH="/home/ga/Documents/hec_ras_results/flood_arrival_times.csv"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
if [ ! -f "$HDF_FILE" ]; then
    HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
fi

# 3. Generate Ground Truth (Run a trusted script inside the env to verify the current HDF)
# This handles cases where the sim might have been re-run with slightly different params
GT_SCRIPT="/tmp/generate_ground_truth.py"
GT_OUTPUT="/tmp/ground_truth_arrival.csv"

cat > "$GT_SCRIPT" << 'EOF'
import h5py
import numpy as np
import pandas as pd
import sys

hdf_path = sys.argv[1]
output_path = sys.argv[2]
threshold = 8.0

try:
    with h5py.File(hdf_path, 'r') as f:
        # Get Cross Section Names/River Stations
        # Path varies slightly by version, trying standard 6.x paths
        try:
            # Try to get River Stations directly
            rs_data = f['Geometry/Cross Sections/Attributes'][()]
            # Extract RS name (usually first column or specific named field)
            # This is complex in HDF, let's look for "River Stations" dataset if it exists
            # often stored as byte strings in a dataset
            river_stations = [x.decode('utf-8').strip() for x in f['Geometry/Cross Sections/River Stations'][()]]
        except:
            # Fallback for some HEC-RAS versions
            river_stations = [f"XS_{i}" for i in range(100)] # Placeholder if fail

        # Get Time Steps (to convert index to hours)
        # HEC-RAS usually stores time as string "ddMMMyyyy HH:mm:ss"
        # We can approximate step size or try to parse
        # Simplified: usually fixed step. Let's assume time series array length.
        # Ideally, we calculate based on step size.
        # For Muncie, it's often 1-hour output or similar.
        # Let's count steps.
        
        # Get Water Surface Elevation
        wse_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'
        wse_data = f[wse_path][()] # Shape: (Time, XS) or (XS, Time) - usually (Time, XS)
        
        # Determine shape
        if wse_data.shape[0] == len(river_stations):
            wse_data = wse_data.T # Make it (Time, XS)
            
        # Get Invert Elevations
        # Usually in Geometry/Cross Sections/Station Elevation
        # This is a bit nested. 
        # Easier alternative: Minimum of the lowest WSE might be close, but risky.
        # Let's look for "Node Attributes" or similar which often has invert.
        # Or iterate through Station-Elevation tables.
        
        inverts = []
        # Accessing variable length arrays for station-elevation
        for i in range(len(river_stations)):
            # In HEC-RAS HDF, specific paths can be tricky. 
            # We will use a reliable location if available. 
            # Geometry/Cross Sections/Attributes usually has 'Minimum Elevation'
            # Let's try finding the attribute table.
            try:
                # Column 0 is often River Station, Column 2 or 3 might be invert.
                # Let's calculate from Station Elevation info
                # "Geometry/Cross Sections/Station Elevation Info" contains starting indices
                # "Geometry/Cross Sections/Station Elevation Values" contains data
                
                info = f['Geometry/Cross Sections/Station Elevation Info'][i]
                start_idx = info[0]
                count = info[1]
                vals = f['Geometry/Cross Sections/Station Elevation Values'][start_idx:start_idx+count]
                # vals is usually (Station, Elevation) pairs 
                # flattened or 2D. In 6.6 it's often 2D array (N, 2)
                elevs = vals[:, 1]
                inverts.append(np.min(elevs))
            except:
                # Fallback: estimate from WSE (dangerous but sometimes necessary if schema differs)
                inverts.append(0.0)

        # Calculate Arrival Times
        results = []
        
        # Time interval: Extract from attributes or assume 1 hour if unknown
        # For Muncie example, usually 15 min or 1 hour output.
        # We'll calculate index and let the verifier handle scale if needed, 
        # or try to parse time stamps.
        
        # Attempt to read time stamps
        try:
            time_stamps = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Time Date Stamps'][()]
            # format: b'02JAN2000 24:00:00'
            t0_str = time_stamps[0].decode('utf-8')
            t1_str = time_stamps[1].decode('utf-8')
            from datetime import datetime
            fmt = "%d%b%Y %H:%M:%S"
            dt0 = datetime.strptime(t0_str, fmt)
            dt1 = datetime.strptime(t1_str, fmt)
            dt_hours = (dt1 - dt0).total_seconds() / 3600.0
        except:
            dt_hours = 1.0 # Fallback assumption
            
        for i, rs in enumerate(river_stations):
            inv = inverts[i]
            wse_series = wse_data[:, i]
            depths = wse_series - inv
            
            # Find first index where depth > threshold
            exceed = np.where(depths > threshold)[0]
            
            if len(exceed) > 0:
                idx = exceed[0]
                arrival_time = idx * dt_hours
            else:
                arrival_time = -1.0
                
            results.append({
                'River_Station': rs,
                'Invert_Elev_ft': inv,
                'Arrival_Time_hrs': arrival_time
            })
            
    df = pd.DataFrame(results)
    df.to_csv(output_path, index=False)
    print("Ground truth generated successfully")
    
except Exception as e:
    print(f"Error generating ground truth: {e}")
    # Write empty file to signal failure
    with open(output_path, 'w') as f:
        f.write("ERROR")
EOF

# Execute Ground Truth Generator (Hidden from agent)
python3 "$GT_SCRIPT" "$HDF_FILE" "$GT_OUTPUT" > /tmp/gt_generation.log 2>&1

# 4. Check Agent Output Status
OUTPUT_EXISTS="false"
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 5. Prepare JSON Result
# We will copy the files out, so the JSON mainly tracks metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "ground_truth_generated": $([ -f "$GT_OUTPUT" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# 6. Secure Copy files to /tmp for extraction
# The verifier needs: result.json, flood_arrival_times.csv (agent), ground_truth_arrival.csv
mkdir -p /tmp/task_result
cp "$TEMP_JSON" /tmp/task_result/result.json
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/task_result/agent_output.csv
fi
if [ -f "$GT_OUTPUT" ]; then
    cp "$GT_OUTPUT" /tmp/task_result/ground_truth.csv
fi
chmod -R 666 /tmp/task_result

# Cleanup
rm -f "$TEMP_JSON" "$GT_SCRIPT" "$GT_OUTPUT"

echo "Result export complete."