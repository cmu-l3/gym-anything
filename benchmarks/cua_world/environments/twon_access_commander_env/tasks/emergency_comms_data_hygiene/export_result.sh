#!/bin/bash
echo "=== Exporting emergency_comms_data_hygiene results ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch final user states via API
cat << 'EOF' > /tmp/fetch_final.py
import sys, json, requests
import urllib3
urllib3.disable_warnings()

AC_URL = "https://localhost:9443"
s = requests.Session()
s.verify = False

try:
    s.put(f"{AC_URL}/api/v3/auth", json={"login": "admin", "password": "2n"}, timeout=10)
    users = s.get(f"{AC_URL}/api/v3/users", timeout=10).json()
    with open('/tmp/final_users.json', 'w') as f:
        json.dump(users, f)
except Exception as e:
    with open('/tmp/final_users.json', 'w') as f:
        json.dump({"error": str(e)}, f)
EOF

python3 /tmp/fetch_final.py
chmod 666 /tmp/final_users.json 2>/dev/null || sudo chmod 666 /tmp/final_users.json 2>/dev/null || true

# Check report file
REPORT_PATH="/home/ga/Documents/emns_remediation.txt"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    REPORT_CONTENT=$(cat "$REPORT_PATH" | jq -Rs .)
else
    REPORT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    REPORT_MTIME="0"
    REPORT_CONTENT="\"\""
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content": $REPORT_CONTENT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="