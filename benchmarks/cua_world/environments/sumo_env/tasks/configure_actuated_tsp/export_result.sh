#!/bin/bash
echo "=== Exporting configure_actuated_tsp result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if TLS file was modified
TLS_MODIFIED="false"
if [ -f "$WORK_DIR/pasubio_tls.add.xml" ]; then
    TLS_MTIME=$(stat -c %Y "$WORK_DIR/pasubio_tls.add.xml" 2>/dev/null || echo "0")
    if [ "$TLS_MTIME" -gt "$TASK_START" ]; then
        TLS_MODIFIED="true"
    fi
fi

# Check outputs
TRIPINFO_EXISTS="false"
if [ -f "$WORK_DIR/tripinfos.xml" ]; then
    TRIPINFO_EXISTS="true"
fi

REPORT_EXISTS="false"
if [ -f "$OUTPUT_DIR/bus_travel_times.txt" ]; then
    REPORT_EXISTS="true"
fi

# Export metadata to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tls_modified": $TLS_MODIFIED,
    "tripinfo_exists": $TRIPINFO_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="