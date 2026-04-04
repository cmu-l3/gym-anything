#!/bin/bash
set -e
echo "=== Exporting compute_stage_change_rate result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/hec_ras_results/stage_change_rates.csv"
SUMMARY_PATH="/home/ga/Documents/hec_ras_results/stage_change_summary.txt"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check CSV file status
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_ROWS=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    # Count rows (excluding header)
    CSV_ROWS=$(($(wc -l < "$CSV_PATH") - 1))
fi

# 3. Check Summary file status
SUMMARY_EXISTS="false"
SUMMARY_CREATED_DURING_TASK="false"
AGENT_MAX_RISE=-1.0
AGENT_MAX_FALL=-1.0

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SUMMARY_CREATED_DURING_TASK="true"
    fi
    
    # Parse values from summary file using grep/python
    # Look for "Overall_Max_Rise_Rate_ft_per_hr: <value>"
    AGENT_MAX_RISE=$(grep -i "Rise" "$SUMMARY_PATH" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "-1.0")
    AGENT_MAX_FALL=$(grep -i "Fall" "$SUMMARY_PATH" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "-1.0")
fi

# 4. Calculate GROUND TRUTH using Python inside the container
# We do this here because the container has h5py and the HDF file.
# The verifier on the host might not have h5py.
echo "Calculating ground truth from HDF5..."

# Path to HDF file
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"
if [ ! -f "$HDF_FILE" ]; then
    HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"
fi

GT_JSON_FILE="/tmp/ground_truth.json"

if [ -f "$HDF_FILE" ]; then
    python3 -c "
import h5py
import numpy as np
import json
import sys
import os

try:
    hdf_path = '$HDF_FILE'
    if not os.path.exists(hdf_path):
        print(json.dumps({'error': 'HDF file not found'}))
        sys.exit(0)

    with h5py.File(hdf_path, 'r') as f:
        # 1. Find WSE dataset
        wse_ds = None
        for path in ['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface',
                     'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/2D Flow Areas/Water Surface']:
            if path in f:
                wse_ds = f[path]
                break
        
        # Fallback search
        if wse_ds is None:
            def finder(name, obj):
                nonlocal wse_ds
                if wse_ds is None and isinstance(obj, h5py.Dataset) and name.endswith('Water Surface'):
                    wse_ds = obj
            f.visititems(finder)

        if wse_ds is None:
            print(json.dumps({'error': 'Water Surface dataset not found'}))
            sys.exit(0)

        # 2. Get Data (Time x CrossSections)
        data = wse_ds[:]
        num_xs = data.shape[1] if len(data.shape) > 1 else 1
        
        # 3. Get Time
        # Looking for Time dataset in same group or parent
        # Simplifying assumption: fixed interval or extract time
        # For Muncie example, usually 1 hour or 15 min steps. 
        # Let's try to find the Time dataset.
        time_ds = None
        parent = wse_ds.parent
        if 'Time' in parent:
            time_ds = parent['Time']
        elif 'Time Date Stamp' in parent:
            # This is strings, harder to parse in one line, assume 15min/1hr
            pass
        
        # If we can't easily parse time, we look at the range.
        # Muncie example is typically ~2 days. 
        # Let's assume the agent uses the time stored in HDF.
        # We will compute derivatives assuming time is in hours.
        # If 'Time' dataset exists and is float, use it.
        # Otherwise, we might need to rely on the fact that Muncie example is usually hourly output?
        # Actually, to be robust, we should try to read the time.
        
        # Let's try to read the time array as strings and parse
        dt_hours = 1.0 # Default fallback
        
        if 'Time Date Stamp' in parent:
            times = parent['Time Date Stamp'][:]
            # Parse first two to get dt
            try:
                t1 = times[0].decode('utf-8')
                t2 = times[1].decode('utf-8')
                from datetime import datetime
                fmt = '%d%b%Y %H:%M:%S'
                d1 = datetime.strptime(t1, fmt)
                d2 = datetime.strptime(t2, fmt)
                dt_hours = (d2 - d1).total_seconds() / 3600.0
            except:
                pass
        
        # 4. Compute Derivatives
        # data is (Time, XS)
        # diff is (Time-1, XS)
        diffs = np.diff(data, axis=0)
        rates = diffs / dt_hours
        
        # 5. Find Maxima
        max_rise = np.max(rates)
        max_fall = np.abs(np.min(rates)) # Magnitude
        
        result = {
            'hdf_exists': True,
            'num_cross_sections': int(num_xs),
            'actual_max_rise': float(max_rise),
            'actual_max_fall': float(max_fall),
            'dt_hours_detected': float(dt_hours)
        }
        print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$GT_JSON_FILE"
else
    echo '{"hdf_exists": false, "error": "No HDF file"}' > "$GT_JSON_FILE"
fi

# 5. Check if application was running (Text editor or Terminal)
APP_RUNNING="false"
if pgrep -f "gedit" > /dev/null || pgrep -f "gnome-terminal" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create Result JSON
# Merge GT data with file status
python3 -c "
import json
import os

try:
    with open('$GT_JSON_FILE', 'r') as f:
        gt = json.load(f)
except:
    gt = {}

result = {
    'task_start': $TASK_START,
    'csv_exists': '$CSV_EXISTS' == 'true',
    'csv_created_during_task': '$CSV_CREATED_DURING_TASK' == 'true',
    'csv_rows': int('$CSV_ROWS'),
    'summary_exists': '$SUMMARY_EXISTS' == 'true',
    'summary_created_during_task': '$SUMMARY_CREATED_DURING_TASK' == 'true',
    'agent_max_rise': float('$AGENT_MAX_RISE'),
    'agent_max_fall': float('$AGENT_MAX_FALL'),
    'app_was_running': '$APP_RUNNING' == 'true',
    'ground_truth': gt
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="