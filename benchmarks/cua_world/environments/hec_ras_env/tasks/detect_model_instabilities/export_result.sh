#!/bin/bash
echo "=== Exporting detect_model_instabilities results ==="

source /workspace/scripts/task_utils.sh

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for required files and timestamps
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"created_during_task\": true, \"size\": $size, \"path\": \"$fpath\"}"
        else
            echo "{\"exists\": true, \"created_during_task\": false, \"size\": $size, \"path\": \"$fpath\"}"
        fi
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0, \"path\": \"$fpath\"}"
    fi
}

SCRIPT_STATUS=$(check_file "$RESULTS_DIR/instability_detector.py")
REPORT_STATUS=$(check_file "$RESULTS_DIR/instability_report.csv")
PLOT_STATUS=$(check_file "$RESULTS_DIR/worst_instability.png")

# 3. Generate GROUND TRUTH for verification
# We run a hidden python script to calculate the correct values from the HDF file
# This allows the verifier to check accuracy without needing HEC-RAS libs itself
echo "Generating ground truth data..."
cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    with h5py.File('/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf', 'r') as f:
        # Locate data paths (standard RAS HDF structure)
        # 1. Get River Stations
        # Path varies slightly by version, checking common 6.x paths
        geom_path = 'Geometry/Cross Sections/Attributes'
        if geom_path in f:
            rs_data = f[geom_path]['RS Name']
            river_stations = [rs.decode('utf-8') for rs in rs_data]
        else:
            # Fallback for some versions
            geom_path = 'Geometry/Cross Sections/Identifier'
            rs_data = f[geom_path]['River Station']
            river_stations = [rs.decode('utf-8') for rs in rs_data]
            
        # 2. Get WSE data
        # Usually in Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
        wse_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'
        wse_data = f[wse_path][:] # Shape: (Time, CrossSection)
        
        results = []
        
        # Calculate Oscillation Index for each XS
        # OI = Sum(|dt|) / (Max - Min)
        for i, rs in enumerate(river_stations):
            series = wse_data[:, i]
            # Filter out NaNs if any
            valid_series = series[~np.isnan(series)]
            
            if len(valid_series) < 2:
                continue
                
            wse_max = np.max(valid_series)
            wse_min = np.min(valid_series)
            wse_range = wse_max - wse_min
            
            diffs = np.abs(np.diff(valid_series))
            total_variation = np.sum(diffs)
            
            if wse_range > 0.001: # Avoid divide by zero for dry/static channels
                oi = total_variation / wse_range
            else:
                oi = 0.0
                
            results.append({
                "RiverStation": rs,
                "OscillationIndex": float(oi),
                "TotalVariation": float(total_variation),
                "Range": float(wse_range)
            })
            
        # Sort by OI descending
        results.sort(key=lambda x: x["OscillationIndex"], reverse=True)
        
        # output top 5 for verification
        print(json.dumps(results[:5]))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

GROUND_TRUTH_JSON=$(python3 /tmp/generate_ground_truth.py)

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_file": $SCRIPT_STATUS,
    "report_file": $REPORT_STATUS,
    "plot_file": $PLOT_STATUS,
    "ground_truth_top_5": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save artifacts for the verifier to copy
# Move JSON to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy agent's output files to /tmp so verifier can copy_from_env
if [ -f "$RESULTS_DIR/instability_report.csv" ]; then
    cp "$RESULTS_DIR/instability_report.csv" /tmp/agent_report.csv
    chmod 666 /tmp/agent_report.csv
fi
if [ -f "$RESULTS_DIR/worst_instability.png" ]; then
    cp "$RESULTS_DIR/worst_instability.png" /tmp/agent_plot.png
    chmod 666 /tmp/agent_plot.png
fi

rm -f "$TEMP_JSON"
echo "Result export complete."
cat /tmp/task_result.json