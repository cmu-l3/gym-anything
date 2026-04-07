#!/bin/bash
# Export script for Audit Key Holders task

echo "=== Exporting Audit Key Holders Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi
if ! type escape_json &>/dev/null; then
    escape_json() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check System Status
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
else
    VISTA_STATUS="stopped"
fi

CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null || docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)

# 4. Check Browser State
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
[ -n "$BROWSER_TITLE" ] && BROWSER_OPEN="true"

# 5. Extract Ground Truth from Database
# We query ^XUSEC("XUPROG") to see which DUZs actually have the key.
# This helps the verifier know what numbers to look for in the screenshot.
echo "Querying ground truth for XUPROG holders..."
HOLDERS_LIST=""
if [ "$VISTA_STATUS" = "running" ]; then
    # Query: Iterate X from 0, print X if ^XUSEC("XUPROG", X) exists
    HOLDERS_LIST=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=0 F  S X=\$O(^XUSEC(\"XUPROG\",X)) Q:X=\"\"  W X,\",\""' 2>/dev/null)
fi
echo "Holders Found: $HOLDERS_LIST"

# 6. Build Result JSON
BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
HOLDERS_LIST_ESC=$(escape_json "$HOLDERS_LIST")

cat > /tmp/audit_key_holders_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "ground_truth": {
        "key_name": "XUPROG",
        "holders": "$HOLDERS_LIST_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/audit_key_holders_result.json"
cat /tmp/audit_key_holders_result.json
echo "=== Export Complete ==="