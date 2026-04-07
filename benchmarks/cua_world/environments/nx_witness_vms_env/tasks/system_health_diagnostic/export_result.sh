#!/bin/bash
echo "=== Exporting system_health_diagnostic results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 2. Check Agent Output File
REPORT_PATH="/home/ga/reports/system_health_report.json"
REPORT_EXISTS="false"
REPORT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture "Ground Truth" via API (to compare against agent report)
# We must do this inside the container because the verifier runs on the host
# and cannot access localhost:7001 directly.

NX_TOKEN=$(refresh_nx_token)
NX_BASE="https://localhost:7001"

echo "Capturing ground truth data from API..."

# Fetch live data
GT_SYSTEM=$(curl -sk "${NX_BASE}/rest/v1/system/info" -H "Authorization: Bearer ${NX_TOKEN}" 2>/dev/null || echo "{}")
GT_SERVERS=$(curl -sk "${NX_BASE}/rest/v1/servers" -H "Authorization: Bearer ${NX_TOKEN}" 2>/dev/null || echo "[]")
GT_DEVICES=$(curl -sk "${NX_BASE}/rest/v1/devices" -H "Authorization: Bearer ${NX_TOKEN}" 2>/dev/null || echo "[]")
GT_USERS=$(curl -sk "${NX_BASE}/rest/v1/users" -H "Authorization: Bearer ${NX_TOKEN}" 2>/dev/null || echo "[]")

# Extract key verification metrics
GT_SYSTEM_NAME=$(echo "$GT_SYSTEM" | python3 -c "import sys,json; print(json.load(sys.stdin).get('systemName',''))" 2>/dev/null || echo "")
GT_SERVER_VERSION=$(echo "$GT_SERVERS" | python3 -c "import sys,json; s=json.load(sys.stdin); print(s[0].get('version','') if s else '')" 2>/dev/null || echo "")
GT_CAM_COUNT=$(echo "$GT_DEVICES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
GT_USER_COUNT=$(echo "$GT_USERS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth": {
        "system_name": "$GT_SYSTEM_NAME",
        "server_version": "$GT_SERVER_VERSION",
        "camera_count": $GT_CAM_COUNT,
        "user_count": $GT_USER_COUNT
    }
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"