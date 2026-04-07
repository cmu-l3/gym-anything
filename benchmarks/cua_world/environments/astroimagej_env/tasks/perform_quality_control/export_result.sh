#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Quality Control Task Result ==="

take_screenshot /tmp/task_end_screenshot.png

REPORT_FILE="/home/ga/Desktop/bad_frames.txt"
REPORT_EXISTS="false"
REPORT_MTIME="0"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

TEMP_JSON=$(mktemp /tmp/qc_result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json
import os

report_file = "/home/ga/Desktop/bad_frames.txt"
content = ""
if os.path.exists(report_file):
    try:
        with open(report_file, 'r', encoding='utf-8') as f:
            content = f.read()[:2000] # Limit size to prevent massive log dumps
    except Exception:
        pass

result = {
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_content": content,
    "report_mtime": int("$REPORT_MTIME"),
    "task_start_time": int("$TASK_START")
}
print(json.dumps(result, indent=2))
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="