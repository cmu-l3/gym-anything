#!/bin/bash
echo "=== Exporting observatory_dome_sync_commissioning results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Dome simulator is/was running
DOME_RUNNING="false"
if pgrep -f "indi_simulator_dome" > /dev/null; then
    DOME_RUNNING="true"
elif grep -q "indi_simulator_dome" /tmp/indiserver.log 2>/dev/null; then
    DOME_RUNNING="true"
fi

# 2. Check Evidence Screenshot
EVIDENCE_EXISTS="false"
EVIDENCE_MTIME=0
if [ -f "/home/ga/Documents/dome_slaved_evidence.png" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_MTIME=$(stat -c %Y "/home/ga/Documents/dome_slaved_evidence.png" 2>/dev/null || echo "0")
fi

# 3. Read CSV Content
CSV_PATH="/home/ga/Documents/dome_sync_report.csv"
CSV_EXISTS="false"
CSV_MTIME=0
CSV_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_CONTENT=$(cat "$CSV_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DOME_RUNNING_PY=$([ "$DOME_RUNNING" = "true" ] && echo "True" || echo "False")
EVIDENCE_EXISTS_PY=$([ "$EVIDENCE_EXISTS" = "true" ] && echo "True" || echo "False")
CSV_EXISTS_PY=$([ "$CSV_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "dome_running": $DOME_RUNNING_PY,
    "evidence_exists": $EVIDENCE_EXISTS_PY,
    "evidence_mtime": $EVIDENCE_MTIME,
    "csv_exists": $CSV_EXISTS_PY,
    "csv_mtime": $CSV_MTIME,
    "csv_content_b64": "$CSV_CONTENT"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result written to /tmp/task_result.json"
echo "=== Export complete ==="