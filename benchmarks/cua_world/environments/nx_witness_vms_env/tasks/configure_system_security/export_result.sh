#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting security hardening results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Refresh token to ensure we can query API
NX_TOKEN=$(refresh_nx_token)

# 1. Get Final System Settings
echo "Querying final system settings..."
FINAL_SETTINGS_JSON=$(curl -sk "${NX_BASE}/rest/v1/system/settings" \
    -H "Authorization: Bearer ${NX_TOKEN}" --max-time 15 2>/dev/null || echo "{}")

# 2. Check Report File
REPORT_FILE="/home/ga/security_hardening_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read first 1KB of content for verification
    REPORT_CONTENT=$(head -c 1024 "$REPORT_FILE" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
else
    REPORT_CONTENT="\"\""
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_settings": $FINAL_SETTINGS_JSON,
    "report_file": {
        "exists": $REPORT_EXISTS,
        "size_bytes": $REPORT_SIZE,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content_snippet": $REPORT_CONTENT
    },
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="