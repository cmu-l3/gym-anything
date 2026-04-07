#!/bin/bash
echo "=== Exporting generate_demand_jtrrouter result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_DIR="/home/ga/SUMO_Output"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper function to get file info
get_file_info() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        local mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$file_path" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Collect metadata for the 5 expected files
FLOWS_INFO=$(get_file_info "$OUTPUT_DIR/flows.xml")
TURNS_INFO=$(get_file_info "$OUTPUT_DIR/turns.xml")
ROUTES_INFO=$(get_file_info "$OUTPUT_DIR/jtr_routes.rou.xml")
SUMOCFG_INFO=$(get_file_info "$OUTPUT_DIR/jtr.sumocfg")
TRIPINFO_INFO=$(get_file_info "$OUTPUT_DIR/jtr_tripinfo.xml")

# Build the JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "flows": $FLOWS_INFO,
        "turns": $TURNS_INFO,
        "routes": $ROUTES_INFO,
        "sumocfg": $SUMOCFG_INFO,
        "tripinfo": $TRIPINFO_INFO
    },
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