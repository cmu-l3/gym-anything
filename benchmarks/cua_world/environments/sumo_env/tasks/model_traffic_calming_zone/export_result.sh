#!/bin/bash
echo "=== Exporting model_traffic_calming_zone result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_DIR="/home/ga/SUMO_Output"

# Function to safely get file info
get_file_info() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        local mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$file_path" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Collect file metadata
FILE_VSS=$(get_file_info "$OUTPUT_DIR/speed_zone.add.xml")
FILE_CFG=$(get_file_info "$OUTPUT_DIR/run_modified.sumocfg")
FILE_BASE_XML=$(get_file_info "$OUTPUT_DIR/baseline_tripinfo.xml")
FILE_MOD_XML=$(get_file_info "$OUTPUT_DIR/modified_tripinfo.xml")
FILE_REPORT=$(get_file_info "$OUTPUT_DIR/impact_report.txt")

# Copy the actual files to /tmp so they can be easily retrieved by copy_from_env
rm -f /tmp/speed_zone.add.xml /tmp/run_modified.sumocfg /tmp/baseline_tripinfo.xml /tmp/modified_tripinfo.xml /tmp/impact_report.txt
cp "$OUTPUT_DIR/speed_zone.add.xml" /tmp/ 2>/dev/null || true
cp "$OUTPUT_DIR/run_modified.sumocfg" /tmp/ 2>/dev/null || true
cp "$OUTPUT_DIR/baseline_tripinfo.xml" /tmp/ 2>/dev/null || true
cp "$OUTPUT_DIR/modified_tripinfo.xml" /tmp/ 2>/dev/null || true
cp "$OUTPUT_DIR/impact_report.txt" /tmp/ 2>/dev/null || true
chmod 666 /tmp/speed_zone.add.xml /tmp/run_modified.sumocfg /tmp/baseline_tripinfo.xml /tmp/modified_tripinfo.xml /tmp/impact_report.txt 2>/dev/null || true

# Generate summary JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "vss": $FILE_VSS,
        "config": $FILE_CFG,
        "baseline_tripinfo": $FILE_BASE_XML,
        "modified_tripinfo": $FILE_MOD_XML,
        "report": $FILE_REPORT
    }
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="