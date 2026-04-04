#!/bin/bash
echo "=== Exporting compute_flood_attenuation results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_FILE="$RESULTS_DIR/flood_attenuation_data.csv"
REPORT_FILE="$RESULTS_DIR/flood_attenuation_summary.txt"
PLOT_FILE="$RESULTS_DIR/flood_attenuation_plot.png"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"

# Helper to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"created_during_task\": true, \"size\": $size}"
        else
            echo "{\"exists\": true, \"created_during_task\": false, \"size\": $size}"
        fi
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0}"
    fi
}

# Check all expected files
CSV_STATUS=$(check_file "$CSV_FILE")
REPORT_STATUS=$(check_file "$REPORT_FILE")
PLOT_STATUS=$(check_file "$PLOT_FILE")
HDF_STATUS=$(check_file "$HDF_FILE")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_file": $CSV_STATUS,
    "report_file": $REPORT_STATUS,
    "plot_file": $PLOT_STATUS,
    "hdf_file": $HDF_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy the CSV and Report to /tmp for the verifier to access easily via copy_from_env
if [ -f "$CSV_FILE" ]; then
    cp "$CSV_FILE" /tmp/flood_attenuation_data.csv
    chmod 644 /tmp/flood_attenuation_data.csv
fi
if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/flood_attenuation_summary.txt
    chmod 644 /tmp/flood_attenuation_summary.txt
fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="