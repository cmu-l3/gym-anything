#!/bin/bash
echo "=== Exporting analyze_storage_discharge result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/storage_discharge_data.csv"
PLOT_PATH="$RESULTS_DIR/storage_loop.png"
REPORT_PATH="$RESULTS_DIR/muskingum_k.txt"
SCRIPT_PATH="$RESULTS_DIR/calculate_storage.py"

# Function to check file status
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"created_during_task\": true, \"size\": $size, \"path\": \"$path\"}"
        else
            echo "{\"exists\": true, \"created_during_task\": false, \"size\": $size, \"path\": \"$path\"}"
        fi
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0, \"path\": \"$path\"}"
    fi
}

# Check all files
CSV_STATUS=$(check_file "$CSV_PATH")
PLOT_STATUS=$(check_file "$PLOT_PATH")
REPORT_STATUS=$(check_file "$REPORT_PATH")
SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")

# Extract K value if report exists
K_VALUE_EXTRACTED=""
if [ -f "$REPORT_PATH" ]; then
    # Try to find a floating point number associated with K or hours
    K_VALUE_EXTRACTED=$(grep -oE "[0-9]+\.?[0-9]*" "$REPORT_PATH" | head -1)
fi

# Check if simulation results exist (Prerequisite)
SIM_RESULTS_EXIST="false"
if [ -f "$MUNCIE_DIR/Muncie.p04.hdf" ] || [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    SIM_RESULTS_EXIST="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sim_results_exist": $SIM_RESULTS_EXIST,
    "files": {
        "csv": $CSV_STATUS,
        "plot": $PLOT_STATUS,
        "report": $REPORT_STATUS,
        "script": $SCRIPT_STATUS
    },
    "extracted_k_value": "$K_VALUE_EXTRACTED",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

# If files exist, copy them to /tmp for retrieval by verifier
if [ -f "$CSV_PATH" ]; then cp "$CSV_PATH" /tmp/storage_discharge_data.csv; chmod 644 /tmp/storage_discharge_data.csv; fi
if [ -f "$REPORT_PATH" ]; then cp "$REPORT_PATH" /tmp/muskingum_k.txt; chmod 644 /tmp/muskingum_k.txt; fi
if [ -f "$PLOT_PATH" ]; then cp "$PLOT_PATH" /tmp/storage_loop.png; chmod 644 /tmp/storage_loop.png; fi

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="