#!/bin/bash
echo "=== Exporting Task Results ==="

# Record end time and extract start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check application state
APP_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Define target output files
PBR_FILE="${RESULTS_DIR}/pBR322.gb"
RECOMB_FILE="${RESULTS_DIR}/pBR322_insulin_recombinant.gb"
REPORT_FILE="${RESULTS_DIR}/cloning_report.txt"

# Function to check file existence and modification time safely
check_file() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        local mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$file_path" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

PBR_STAT=$(check_file "$PBR_FILE")
RECOMB_STAT=$(check_file "$RECOMB_FILE")
REPORT_STAT=$(check_file "$REPORT_FILE")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "pbr_file": $PBR_STAT,
    "recomb_file": $RECOMB_STAT,
    "report_file": $REPORT_STAT
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