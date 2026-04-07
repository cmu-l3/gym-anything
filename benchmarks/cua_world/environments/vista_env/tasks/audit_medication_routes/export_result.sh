#!/bin/bash
# Export script for Audit Medication Routes task

echo "=== Exporting Audit Medication Routes Result ==="

# Helper function for JSON escaping
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check VistA status
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
fi

# Get Container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null || docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)

# Check YDBGui access
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# Check Browser Title
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
[ -n "$BROWSER_TITLE" ] && BROWSER_OPEN="true"

# ================================================================
# GROUND TRUTH QUERY
# ================================================================
# Verify "INTRAVENOUS" exists in ^PS(51.2) and get its IEN and Data
TARGET_NAME="INTRAVENOUS"
TARGET_EXISTS="false"
TARGET_IEN=""
TARGET_DATA=""

if [ "$VISTA_STATUS" = "running" ]; then
    echo "Querying VistA for '$TARGET_NAME' in ^PS(51.2)..."
    
    # M code to find IEN by name in "B" index: $O(^PS(51.2,"B","INTRAVENOUS",0))
    TARGET_IEN=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'W \$O(^PS(51.2,\"B\",\"$TARGET_NAME\",0))'" 2>/dev/null | tail -1 | tr -d '\r')
    
    if [ -n "$TARGET_IEN" ] && [ "$TARGET_IEN" != "0" ]; then
        TARGET_EXISTS="true"
        # Get data node: ^PS(51.2,IEN,0)
        TARGET_DATA=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'W \$G(^PS(51.2,$TARGET_IEN,0))'" 2>/dev/null | tail -1)
    fi
    echo "Ground Truth: Exists=$TARGET_EXISTS, IEN=$TARGET_IEN, Data=$TARGET_DATA"
fi

# Escape for JSON
BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
TARGET_DATA_ESC=$(escape_json "$TARGET_DATA")

# Save result JSON
cat > /tmp/audit_medication_routes_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "ground_truth": {
        "exists": $TARGET_EXISTS,
        "ien": "$TARGET_IEN",
        "data": "$TARGET_DATA_ESC",
        "target_name": "$TARGET_NAME"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "Result saved to /tmp/audit_medication_routes_result.json"
cat /tmp/audit_medication_routes_result.json
echo "=== Export Complete ==="