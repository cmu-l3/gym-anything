#!/bin/bash
echo "=== Exporting checkpoint_peak_congestion_state result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM framework compatibility
take_screenshot /tmp/task_end.png

# Paths to the expected output files
SUMMARY_FILE="/home/ga/SUMO_Output/summary.xml"
REPORT_FILE="/home/ga/SUMO_Output/peak_report.txt"
STATE_FILE="/home/ga/SUMO_Output/peak_state.xml"

# Extract file metadata (existence and modification times)
SUMMARY_EXISTS="false"
SUMMARY_MTIME=0
if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
fi

REPORT_EXISTS="false"
REPORT_MTIME=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

STATE_EXISTS="false"
STATE_MTIME=0
if [ -f "$STATE_FILE" ]; then
    STATE_EXISTS="true"
    STATE_MTIME=$(stat -c %Y "$STATE_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_mtime": $SUMMARY_MTIME,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "state_exists": $STATE_EXISTS,
    "state_mtime": $STATE_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON payload to the persistent /tmp location with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON prepared and saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="