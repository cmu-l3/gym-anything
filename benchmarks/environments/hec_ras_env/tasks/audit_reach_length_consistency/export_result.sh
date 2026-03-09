#!/bin/bash
echo "=== Exporting audit_reach_length_consistency results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# 1. Generate Ground Truth (Trusted calculation inside container)
# We do this here so we can use the container's environment (h5py, correct HEC-RAS data)
# and export a trusted CSV for the host verifier to compare against.
echo "Generating ground truth data..."

cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import csv
import sys
import numpy as np

hdf_path = sys.argv[1]
output_path = "/tmp/ground_truth.csv"

try:
    with h5py.File(hdf_path, 'r') as f:
        # Check structure - HEC-RAS HDF structure varies slightly by version
        # Typically /Geometry/Cross Sections/Attributes or /Geometry/Cross Sections/River Stations
        
        # We need to map River/Reach/RS to their data
        # HEC-RAS stores data in parallel arrays usually
        
        # Reading River Names and Reach Names
        # Usually in /Geometry/Cross Sections/Attributes
        
        g_xs = f['Geometry/Cross Sections']
        
        # Get River Stations (strings)
        river_stations = g_xs['River Stations'][()].astype(str)
        
        # Get River and Reach names (often indexed or direct strings)
        # In some versions, they are in 'Attributes' table
        # Let's try to find the 'Channel Reach Length' dataset
        # It is often in /Geometry/Cross Sections/Attributes -> column 'Reach Length' or similar
        # OR /Geometry/Cross Sections/Reach Lengths
        
        # Robust approach: Look for specific datasets
        # Note: In HEC-RAS 6.x HDF:
        # /Geometry/Cross Sections/Attributes is a compound dataset
        attrs = g_xs['Attributes'][()]
        # attrs fields usually include: 'River Name', 'Reach Name', 'River Station', 'Reach Length' (which is channel len)
        
        # Field names in HDF are bytes
        dtype_names = attrs.dtype.names
        
        # Helpers to decode
        def decode(x):
            if isinstance(x, bytes): return x.decode('utf-8').strip()
            return str(x).strip()
            
        data = []
        
        for row in attrs:
            # Extract fields based on available names (handle potential variations)
            r_name = decode(row['River Name']) if 'River Name' in dtype_names else "River"
            r_reach = decode(row['Reach Name']) if 'Reach Name' in dtype_names else "Reach"
            r_station = decode(row['River Station']) if 'River Station' in dtype_names else "0"
            
            # Lengths: usually 'Length Ch' or 'Reach Length'
            # Let's look for channel length
            if 'Length Ch' in dtype_names:
                stored_len = float(row['Length Ch'])
            elif 'Reach Length' in dtype_names:
                stored_len = float(row['Reach Length'])
            else:
                stored_len = 0.0
            
            # Convert RS to float for calculation
            try:
                rs_val = float(r_station)
            except:
                rs_val = 0.0
                
            data.append({
                'River': r_name,
                'Reach': r_reach,
                'RS': r_station,
                'RS_Val': rs_val,
                'Stored_Len': stored_len
            })
            
        # Sort by River, Reach, RS (descending for RS usually upstream->downstream)
        # HEC-RAS conventions: High RS is upstream.
        data.sort(key=lambda x: (x['River'], x['Reach'], -x['RS_Val']))
        
        results = []
        for i, current in enumerate(data):
            # Check if next item is same river/reach
            if i + 1 < len(data) and data[i+1]['River'] == current['River'] and data[i+1]['Reach'] == current['Reach']:
                next_node = data[i+1]
                implied = current['RS_Val'] - next_node['RS_Val']
            else:
                implied = 0.0 # Downstream boundary
            
            discrepancy = abs(implied - current['Stored_Len'])
            # Logic: If implied is 0 (last node), discrepancy might be high if stored length > 0
            # BUT: HEC-RAS last node length usually refers to distance to next junction or 0.
            # For this task, we follow the prompt logic: "Implied = Current - Next". 
            # If no next, Implied is undefined. We'll set discrepancy to 0 for last node to avoid false positives 
            # unless the task explicitly asked to check it (it said "Most downstream ... is N/A").
            
            if i + 1 < len(data) and data[i+1]['River'] == current['River'] and data[i+1]['Reach'] == current['Reach']:
                status = "FAIL" if discrepancy > 1.0 else "PASS"
            else:
                discrepancy = 0.0 # Ignore last node
                status = "PASS"
                
            results.append({
                'River': current['River'],
                'Reach': current['Reach'],
                'River_Station': current['RS'],
                'Stored_Length': current['Stored_Len'],
                'Implied_Length': implied,
                'Discrepancy': discrepancy,
                'Status': status
            })

    # Write to CSV
    with open(output_path, 'w', newline='') as csvfile:
        fieldnames = ['River', 'Reach', 'River_Station', 'Stored_Length', 'Implied_Length', 'Discrepancy', 'Status']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for row in results:
            writer.writerow(row)
            
    print(f"Ground truth generated with {len(results)} rows.")

except Exception as e:
    print(f"Error generating ground truth: {e}")
    sys.exit(1)
PYEOF

python3 /tmp/generate_ground_truth.py "$HDF_FILE" > /tmp/gt_gen.log 2>&1

# 2. Check Agent Outputs
AGENT_SCRIPT="$RESULTS_DIR/audit_reach_lengths.py"
AGENT_CSV="$RESULTS_DIR/reach_length_audit.csv"
AGENT_SUMMARY="$RESULTS_DIR/audit_summary.txt"

SCRIPT_EXISTS="false"
CSV_EXISTS="false"
SUMMARY_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$AGENT_SCRIPT" ]; then SCRIPT_EXISTS="true"; fi

if [ -f "$AGENT_CSV" ]; then 
    CSV_EXISTS="true"
    # Check timestamp
    F_TIME=$(stat -c %Y "$AGENT_CSV" 2>/dev/null || echo "0")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$AGENT_SUMMARY" ]; then SUMMARY_EXISTS="true"; fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "summary_exists": $SUMMARY_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_timestamp": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move files for verifier to access via copy_from_env
# We need to expose: result.json, agent's CSV, ground truth CSV
cp "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

if [ "$CSV_EXISTS" = "true" ]; then
    cp "$AGENT_CSV" /tmp/agent_audit.csv
    chmod 644 /tmp/agent_audit.csv
fi

if [ -f "/tmp/ground_truth.csv" ]; then
    chmod 644 /tmp/ground_truth.csv
fi

# Clean up
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="