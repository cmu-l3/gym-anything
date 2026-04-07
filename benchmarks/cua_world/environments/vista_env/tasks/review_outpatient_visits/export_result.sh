#!/bin/bash
# Export script for Review Outpatient Visits task

echo "=== Exporting Review Outpatient Visits Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

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

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check VistA container status
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="stopped"
else
    VISTA_STATUS="not_found"
fi

# Get container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null || docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)

# Check YDBGui accessibility
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# Browser state
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
if [ -n "$BROWSER_TITLE" ]; then
    BROWSER_OPEN="true"
fi

# Query sample visit data for ground truth verification
# We get the first 5 visits to see what they look like
VISIT_DATA_EXISTS="false"
SAMPLE_VISITS=""

if [ "$VISTA_STATUS" = "running" ]; then
    echo "Querying sample visit data..."
    # Query: Iterate ^AUPNVSIT, get first 5 entries, output IEN and 0-node
    SAMPLE_VISITS=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S U=\"^\",X=0,N=0 F  S X=\$O(^AUPNVSIT(X)) Q:X=\"\"!(N>=5)  I X?1.N S N=N+1 W \"IEN:\",X,\" Data:\",\$E(\$G(^AUPNVSIT(X,0)),1,60),\";\""' 2>/dev/null | tail -1)
    
    if [ -n "$SAMPLE_VISITS" ]; then
        VISIT_DATA_EXISTS="true"
    fi
fi

BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
SAMPLE_VISITS_ESC=$(escape_json "$SAMPLE_VISITS")

# Create result JSON
cat > /tmp/review_outpatient_visits_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "database_verification": {
        "visit_data_exists": $VISIT_DATA_EXISTS,
        "sample_visits": "$SAMPLE_VISITS_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "Result saved to /tmp/review_outpatient_visits_result.json"
cat /tmp/review_outpatient_visits_result.json

echo ""
echo "=== Export Complete ==="