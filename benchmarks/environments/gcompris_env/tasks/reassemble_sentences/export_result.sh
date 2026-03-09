#!/bin/bash
echo "=== Exporting Reassemble Sentences result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

REPORT_PATH="/home/ga/Documents/sentence_report.txt"
EVIDENCE_PATH="/home/ga/Documents/sentence_evidence.png"

# Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# Check Evidence Screenshot
EVIDENCE_EXISTS="false"
EVIDENCE_CREATED_DURING="false"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING="true"
    fi
fi

# Check App State
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Capture final system screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_size_bytes": $REPORT_SIZE,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_created_during_task": $EVIDENCE_CREATED_DURING,
    "app_running": $APP_RUNNING
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="