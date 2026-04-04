#!/bin/bash
set -e

echo "=== Exporting Geography Puzzle Task Result ==="

source /workspace/scripts/task_utils.sh

# Load task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot (system snapshot for verification)
take_screenshot /tmp/task_final_state.png

# Check 1: Is GCompris still running?
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# Check 2: Did the agent create the evidence screenshot?
EVIDENCE_PATH="/home/ga/geography_result.png"
EVIDENCE_EXISTS="false"
EVIDENCE_VALID="false"
EVIDENCE_SIZE="0"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c%s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    FILE_MOD=$(stat -c%Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    
    # Check if created AFTER task start and has reasonable size (>10KB)
    if [ "$FILE_MOD" -gt "$TASK_START" ] && [ "$EVIDENCE_SIZE" -gt 10000 ]; then
        EVIDENCE_VALID="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_valid": $EVIDENCE_VALID,
    "evidence_size_bytes": $EVIDENCE_SIZE,
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"