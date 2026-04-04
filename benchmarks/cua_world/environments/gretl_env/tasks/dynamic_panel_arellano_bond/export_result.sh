#!/bin/bash
echo "=== Exporting Dynamic Panel Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DATASET_PATH="/home/ga/Documents/gretl_data/abdata.gdt"
SCRIPT_PATH="/home/ga/Documents/gretl_output/dynamic_panel.inp"
RESULTS_PATH="/home/ga/Documents/gretl_output/dpanel_results.txt"
PVALUE_PATH="/home/ga/Documents/gretl_output/ar2_pvalue.txt"

# Helper to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"modified\": true, \"size\": $size}"
        else
            echo "{\"exists\": true, \"modified\": false, \"size\": $size}"
        fi
    else
        echo "{\"exists\": false, \"modified\": false, \"size\": 0}"
    fi
}

# Check files
DATASET_STATUS=$(check_file "$DATASET_PATH")
SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")
RESULTS_STATUS=$(check_file "$RESULTS_PATH")
PVALUE_STATUS=$(check_file "$PVALUE_PATH")

# Check if Gretl is running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "dataset": $DATASET_STATUS,
    "script": $SCRIPT_STATUS,
    "results": $RESULTS_STATUS,
    "pvalue_file": $PVALUE_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="