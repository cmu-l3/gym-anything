#!/bin/bash
echo "=== Exporting XOR Gate from Basic Gates result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of current screen state
take_screenshot /tmp/task_final.png

# Check agent's evidence screenshot
EVIDENCE_PATH="/home/ga/Documents/xor_circuit.png"
EVIDENCE_EXISTS="false"
EVIDENCE_VALID="false"
EVIDENCE_SIZE="0"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        EVIDENCE_VALID="true"
    fi
fi

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_valid_timestamp": $EVIDENCE_VALID,
    "evidence_size_bytes": $EVIDENCE_SIZE,
    "final_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_path": "$EVIDENCE_PATH"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
