#!/bin/bash
echo "=== Exporting evaluate_hov_lane_policy result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot for trajectory VLM verification
take_screenshot /tmp/task_final.png ga

# Files to check
ROUTE_FILE="/home/ga/SUMO_Output/hov_demand.rou.xml"
SCRIPT_FILE="/home/ga/SUMO_Output/run_hov_sim.py"
TRIPINFO_FILE="/home/ga/SUMO_Output/tripinfo.xml"
ANALYSIS_FILE="/home/ga/SUMO_Output/hov_analysis.txt"

check_file() {
    if [ -f "$1" ]; then
        MTIME=$(stat -c %Y "$1" 2>/dev/null || echo "0")
        SIZE=$(stat -c %s "$1" 2>/dev/null || echo "0")
        CREATED_DURING="false"
        if [ "$MTIME" -gt "$TASK_START" ]; then
            CREATED_DURING="true"
        fi
        echo "{\"exists\": true, \"size\": $SIZE, \"created_during_task\": $CREATED_DURING}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

ROUTE_STAT=$(check_file "$ROUTE_FILE")
SCRIPT_STAT=$(check_file "$SCRIPT_FILE")
TRIPINFO_STAT=$(check_file "$TRIPINFO_FILE")
ANALYSIS_STAT=$(check_file "$ANALYSIS_FILE")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "route_file": $ROUTE_STAT,
    "script_file": $SCRIPT_STAT,
    "tripinfo_file": $TRIPINFO_STAT,
    "analysis_file": $ANALYSIS_STAT,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="