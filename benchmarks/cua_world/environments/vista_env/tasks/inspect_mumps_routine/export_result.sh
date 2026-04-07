#!/bin/bash
set -e

echo "=== Exporting Inspect MUMPS Routine Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 2. Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Check VistA Status
VISTA_STATUS="stopped"
if docker ps --filter "name=vista-vehu" --filter "status=running" -q | grep -q .; then
    VISTA_STATUS="running"
fi

# 4. Check YDBGui Access
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    if curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" | grep -q "200"; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# 5. Browser Info
BROWSER_OPEN="false"
BROWSER_TITLE=""
if DISPLAY=:1 wmctrl -l | grep -qi "firefox"; then
    BROWSER_OPEN="true"
    BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | head -1)
fi

# 6. Prepare Ground Truth for Export (safely escaped)
GT_CONTENT=""
if [ -f /tmp/xlfdt_sample.txt ]; then
    # Read first 10 lines and escape for JSON
    GT_CONTENT=$(head -n 10 /tmp/xlfdt_sample.txt | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
else
    GT_CONTENT="\"\""
fi

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vista_status": "$VISTA_STATUS",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_open": $BROWSER_OPEN,
    "browser_title": "$(echo $BROWSER_TITLE | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read().strip())[1:-1])')",
    "ground_truth_sample": $GT_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 8. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"