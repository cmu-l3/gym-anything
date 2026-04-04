#!/bin/bash
echo "=== Exporting extract_longitudinal_profile results ==="

source /workspace/scripts/task_utils.sh

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Function to check file status
check_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local size=$(stat -c %s "$filepath")
        local mtime=$(stat -c %Y "$filepath")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check all expected files
CSV_STATUS=$(check_file "$RESULTS_DIR/longitudinal_profile.csv")
PLOT_STATUS=$(check_file "$RESULTS_DIR/longitudinal_profile.png")
SUMMARY_STATUS=$(check_file "$RESULTS_DIR/profile_summary.txt")
SCRIPT_STATUS=$(check_file "$RESULTS_DIR/extract_profile.py")

# Check if HEC-RAS simulation was run (result file exists and is new)
HDF_STATUS=$(check_file "$MUNCIE_DIR/Muncie.p04.hdf")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_file": $CSV_STATUS,
    "plot_file": $PLOT_STATUS,
    "summary_file": $SUMMARY_STATUS,
    "script_file": $SCRIPT_STATUS,
    "hdf_result_file": $HDF_STATUS,
    "results_dir": "$RESULTS_DIR",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="