#!/bin/bash
echo "=== Exporting simulate_motorcycle_lane_splitting result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper function to check file stats
check_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local created="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check all required files
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

MOTO_ROU=$(check_file "${WORK_DIR}/motorcycles.rou.xml")
CONFIG=$(check_file "${WORK_DIR}/run_sublane.sumocfg")
TRIPINFO=$(check_file "${OUTPUT_DIR}/sublane_tripinfos.xml")
REPORT=$(check_file "${OUTPUT_DIR}/mode_comparison.txt")

# Create JSON result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "motorcycles_rou": $MOTO_ROU,
        "run_config": $CONFIG,
        "tripinfo": $TRIPINFO,
        "report": $REPORT
    }
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