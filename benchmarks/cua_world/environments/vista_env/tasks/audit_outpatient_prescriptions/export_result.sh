#!/bin/bash
# Export script for Audit Outpatient Prescriptions task

echo "=== Exporting Audit Outpatient Prescriptions Result ==="

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

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check VistA container
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="stopped"
else
    VISTA_STATUS="not_found"
fi

CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null || docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)

# Check YDBGui accessibility
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# Check Browser State
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
if [ -n "$BROWSER_TITLE" ]; then
    BROWSER_OPEN="true"
fi

# -----------------------------------------------------------------------------
# DATABASE VERIFICATION: Confirm data existence for the verifier
# -----------------------------------------------------------------------------
RX_DATA_EXISTS="false"
SAMPLE_REFILL_DATA=""
TARGET_IEN=$(cat /tmp/target_rx_ien.txt 2>/dev/null || echo "")

if [ "$VISTA_STATUS" = "running" ] && [ -n "$TARGET_IEN" ]; then
    # Query the refill node 1 for the target IEN to demonstrate ground truth
    # Query: Iterate subnode 1 to get first refill entry
    echo "Querying refill data for IEN $TARGET_IEN..."
    
    # Check if node 1 exists
    NODE_CHECK=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'I \$D(^PSRX($TARGET_IEN,1)) W \"YES\"'" 2>/dev/null | tail -1)
    
    if [[ "$NODE_CHECK" == *"YES"* ]]; then
        RX_DATA_EXISTS="true"
        # Extract first refill data string
        SAMPLE_REFILL_DATA=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'S R=\$O(^PSRX($TARGET_IEN,1,0)) I R W \$G(^PSRX($TARGET_IEN,1,R,0))'" 2>/dev/null | tail -1)
    fi
fi

# Escape JSON strings
BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
SAMPLE_REFILL_DATA_ESC=$(escape_json "$SAMPLE_REFILL_DATA")

# Construct Result JSON
cat > /tmp/audit_outpatient_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "target_ien": "$TARGET_IEN",
    "database_verification": {
        "refill_data_exists": $RX_DATA_EXISTS,
        "sample_refill_data": "$SAMPLE_REFILL_DATA_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "Result saved to /tmp/audit_outpatient_result.json"
cat /tmp/audit_outpatient_result.json

echo ""
echo "=== Export Complete ==="