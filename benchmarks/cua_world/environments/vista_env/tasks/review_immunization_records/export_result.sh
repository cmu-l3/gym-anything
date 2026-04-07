#!/bin/bash
# Export script for Review Immunization Records task

echo "=== Exporting Review Immunization Records Result ==="

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

# Check YDBGui Accessibility
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

# -----------------------------------------------------------------------------
# Collect Ground Truth Data for Verification
# -----------------------------------------------------------------------------
AUTNIMM_EXISTS=$(cat /tmp/autnimm_exists 2>/dev/null || echo "false")
AUPNVIMM_EXISTS=$(cat /tmp/aupnvimm_exists 2>/dev/null || echo "false")
SAMPLE_VACCINES=$(cat /tmp/sample_vaccines.txt 2>/dev/null || echo "")

# If container is running, grab fresh samples (in case they changed or setup failed)
if [ "$VISTA_STATUS" = "running" ]; then
    # Get 3 Immunization Types (AUTNIMM)
    FRESH_AUTNIMM=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S U=\"^\",X=0,N=0 F  S X=\$O(^AUTNIMM(X)) Q:X=\"\"!(N>=3)  S N=N+1 W \$P(\$G(^AUTNIMM(X,0)),U,1),\";\""' 2>/dev/null | tail -1)
    
    # Get 3 Vaccination Events (AUPNVIMM)
    FRESH_AUPNVIMM=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S U=\"^\",X=0,N=0 F  S X=\$O(^AUPNVIMM(X)) Q:X=\"\"!(N>=3)  S N=N+1 W \"DFN:\"_\$P(\$G(^AUPNVIMM(X,0)),U,2)_\",\""' 2>/dev/null | tail -1)
else
    FRESH_AUTNIMM=""
    FRESH_AUPNVIMM=""
fi

BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
FRESH_AUTNIMM_ESC=$(escape_json "$FRESH_AUTNIMM")
FRESH_AUPNVIMM_ESC=$(escape_json "$FRESH_AUPNVIMM")

# Create Result JSON
cat > /tmp/review_immunization_records_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "ground_truth": {
        "autnimm_exists": $AUTNIMM_EXISTS,
        "aupnvimm_exists": $AUPNVIMM_EXISTS,
        "sample_vaccines": "$FRESH_AUTNIMM_ESC",
        "sample_events": "$FRESH_AUPNVIMM_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "Result saved to /tmp/review_immunization_records_result.json"
cat /tmp/review_immunization_records_result.json

echo ""
echo "=== Export Complete ==="