#!/bin/bash
echo "=== Exporting optimize_tls_offset_sweep result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target files
SCRIPT_PATH="/home/ga/SUMO_Output/optimize_offset.py"
CSV_PATH="/home/ga/SUMO_Output/offset_results.csv"
XML_PATH="/home/ga/SUMO_Output/best_tls.add.xml"

# Helper function to check file stats
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local created="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created="true"
        fi
        echo "{\"exists\": true, \"created_during_task\": $created, \"size\": $size}"
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0}"
    fi
}

SCRIPT_STAT=$(check_file "$SCRIPT_PATH")
CSV_STAT=$(check_file "$CSV_PATH")
XML_STAT=$(check_file "$XML_PATH")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_file": $SCRIPT_STAT,
    "csv_file": $CSV_STAT,
    "xml_file": $XML_STAT
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="