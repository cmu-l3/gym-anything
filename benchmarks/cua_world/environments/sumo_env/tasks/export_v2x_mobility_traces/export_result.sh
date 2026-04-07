#!/bin/bash
echo "=== Exporting result for export_v2x_mobility_traces ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
FCD_FILE="/home/ga/SUMO_Output/acosta_fcd.xml"
MOBILITY_FILE="/home/ga/SUMO_Output/ns2_mobility.tcl"
ACTIVITY_FILE="/home/ga/SUMO_Output/ns2_activity.tcl"
SUMMARY_FILE="/home/ga/SUMO_Output/trace_summary.txt"

check_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

FCD_JSON=$(check_file "$FCD_FILE")
MOBILITY_JSON=$(check_file "$MOBILITY_FILE")
ACTIVITY_JSON=$(check_file "$ACTIVITY_FILE")
SUMMARY_JSON=$(check_file "$SUMMARY_FILE")

# Extract max timestamp from NS2 mobility file to verify --end parameter
MAX_TIME_FOUND="-1"
if [ -f "$MOBILITY_FILE" ]; then
    # Look for the highest timestamp in lines like '$ns_ at 123.45 "$node_(0)..."'
    MAX_TIME=$(grep -oP "\$ns_ at \K[0-9.]+" "$MOBILITY_FILE" | sort -nr | head -n 1 || echo "-1")
    if [ -n "$MAX_TIME" ]; then
        MAX_TIME_FOUND="$MAX_TIME"
    fi
fi

# Create export JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "fcd_file": $FCD_JSON,
    "mobility_file": $MOBILITY_JSON,
    "activity_file": $ACTIVITY_JSON,
    "summary_file": $SUMMARY_JSON,
    "max_time_found": "$MAX_TIME_FOUND",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="