#!/bin/bash
# Export script for Investigate Hospital Locations task

echo "=== Exporting Investigate Hospital Locations Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for screenshot
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi
# Helper for JSON escaping
if ! type escape_json &>/dev/null; then
    escape_json() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g'
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

# Check Browser Window Title
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
if [ -n "$BROWSER_TITLE" ]; then
    BROWSER_OPEN="true"
fi

# Read Ground Truth data captured during setup
GT_DATA=""
if [ -f "/tmp/hospital_locations_gt.txt" ]; then
    GT_DATA=$(cat /tmp/hospital_locations_gt.txt)
fi

# Current query to verify DB is still responsive (Read-only check)
DB_RESPONSIVE="false"
if [ "$VISTA_STATUS" = "running" ]; then
    CHECK_VAL=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W 1"' 2>/dev/null | tail -1)
    if [ "$CHECK_VAL" = "1" ]; then
        DB_RESPONSIVE="true"
    fi
fi

BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
GT_DATA_ESC=$(escape_json "$GT_DATA")

# Create Result JSON
cat > /tmp/investigate_locations_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "db_responsive": $DB_RESPONSIVE,
    "ground_truth_sample": "$GT_DATA_ESC",
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Copy to generic name if needed by framework, though verifier reads specific path
cp /tmp/investigate_locations_result.json /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result saved to /tmp/investigate_locations_result.json"
cat /tmp/investigate_locations_result.json

echo ""
echo "=== Export Complete ==="