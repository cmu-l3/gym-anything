#!/bin/bash
set -e

echo "=== Exporting Configure Breakout Rooms results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot (for VLM analysis)
take_screenshot /tmp/task_final.png

# 2. Gather task metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

EVIDENCE_FILE="/home/ga/breakout_rooms_evidence.png"
EVIDENCE_EXISTS="false"
EVIDENCE_CREATED_DURING_TASK="false"
EVIDENCE_SIZE="0"

if [ -f "$EVIDENCE_FILE" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Firefox is still running
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 3. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_created_during_task": $EVIDENCE_CREATED_DURING_TASK,
    "evidence_size_bytes": $EVIDENCE_SIZE,
    "firefox_running": $FIREFOX_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png",
    "evidence_path": "$EVIDENCE_FILE"
}
EOF

# 4. Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="