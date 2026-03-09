#!/bin/bash
echo "=== Exporting visualize_critical_section results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
PLOT_PATH="$RESULTS_DIR/critical_section_plot.png"
REPORT_PATH="$RESULTS_DIR/critical_section_info.txt"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# 1. Calculate GROUND TRUTH inside the container
# We do this here because the container has the HEC-RAS output file and h5py
echo "Calculating ground truth..."
cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    hdf_path = sys.argv[1]
    
    with h5py.File(hdf_path, 'r') as f:
        # Get River Station list
        # Path varies slightly by version, try standard 6.x paths
        try:
            # Decode bytes to strings
            rs_data = f['Geometry/Cross Sections/River Stations'][()]
            river_stations = [x.decode('utf-8') for x in rs_data]
        except:
            # Fallback path
            rs_data = f['Geometry/Cross Sections/Attributes'][()]['River Station']
            river_stations = [x.decode('utf-8') for x in rs_data]

        max_depth = -1.0
        critical_rs = ""
        
        # Iterate to find max depth
        # WSE path: Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
        # We need the MAX WSE for each XS
        
        # Get WSE data (Time x XS)
        wse_dataset = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface']
        # Get max over time for each XS
        max_wse_per_xs = np.max(wse_dataset, axis=0)
        
        # Get Min Channel Elevation for each XS
        # Attributes table usually has 'Minimum Elevation'
        try:
            min_elevs = f['Geometry/Cross Sections/Attributes'][()]['Minimum Elevation']
        except:
            # Fallback: compute from coordinate points if attribute missing (slower, unlikely needed for Muncie)
            min_elevs = []
            for i in range(len(river_stations)):
                coords = f[f'Geometry/Cross Sections/Station Elevation/{river_stations[i]}'][()]
                min_elevs.append(np.min(coords[:, 1]))
        
        # Calculate depths
        depths = max_wse_per_xs - min_elevs
        
        # Find max
        max_idx = np.argmax(depths)
        max_depth = float(depths[max_idx])
        critical_rs = river_stations[max_idx]
        
    print(json.dumps({
        "ground_truth_station": critical_rs,
        "ground_truth_depth": max_depth
    }))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

GROUND_TRUTH_JSON=$(python3 /tmp/calc_ground_truth.py "$HDF_FILE" 2>/dev/null || echo '{"error": "Script failed"}')
echo "Ground Truth: $GROUND_TRUTH_JSON"

# 2. Check Agent Outputs
PLOT_EXISTS="false"
PLOT_CREATED_DURING_TASK="false"
PLOT_SIZE="0"

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH")
    PLOT_SIZE=$(stat -c %s "$PLOT_PATH")
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED_DURING_TASK="true"
    fi
fi

REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Read first 1000 chars
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED_DURING_TASK,
    "plot_path": "$PLOT_PATH",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R -s .),
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"