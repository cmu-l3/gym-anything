#!/bin/bash
echo "=== Exporting analyze_trip_performance result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
TRIPINFO_PATH="$SCENARIO_DIR/tripinfos.xml"
REPORT_PATH="/home/ga/SUMO_Output/trip_report.txt"

TRIPINFO_EXISTS="false"
TRIPINFO_MTIME=0
TRIPINFO_SIZE=0

REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_SIZE=0

# Check tripinfos.xml
if [ -f "$TRIPINFO_PATH" ]; then
    TRIPINFO_EXISTS="true"
    TRIPINFO_MTIME=$(stat -c %Y "$TRIPINFO_PATH" 2>/dev/null || echo "0")
    TRIPINFO_SIZE=$(stat -c %s "$TRIPINFO_PATH" 2>/dev/null || echo "0")
    
    # Copy to tmp for verifier
    cp "$TRIPINFO_PATH" /tmp/agent_tripinfos.xml
    chmod 666 /tmp/agent_tripinfos.xml
fi

# Check trip_report.txt
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Copy to tmp for verifier
    cp "$REPORT_PATH" /tmp/agent_trip_report.txt
    chmod 666 /tmp/agent_trip_report.txt
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "tripinfo_exists": $TRIPINFO_EXISTS,
    "tripinfo_mtime": $TRIPINFO_MTIME,
    "tripinfo_size_bytes": $TRIPINFO_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_size_bytes": $REPORT_SIZE,
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