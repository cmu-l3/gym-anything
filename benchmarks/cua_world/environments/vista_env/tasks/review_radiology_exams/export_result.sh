#!/bin/bash
# Export script for Review Radiology Exams task
# Captures final state and queries VistA for ground truth data to verify against.

echo "=== Exporting Review Radiology Exams Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Infrastructure
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
else
    VISTA_STATUS="stopped"
fi

CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# 4. Check Browser State
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
if [ -n "$BROWSER_TITLE" ]; then
    BROWSER_OPEN="true"
fi

# 5. Query Ground Truth Data (What SHOULD be seen?)
# This allows the verifier to know if the agent found real data.

SAMPLE_PROCEDURES=""
SAMPLE_ORDERS=""
PROCEDURE_COUNT="0"
ORDER_COUNT="0"

if [ "$VISTA_STATUS" = "running" ]; then
    # Helper to clean M output
    clean_m_output() {
        tr -cd '\11\12\15\40-\176' # Keep only printable ASCII + whitespace
    }

    echo "Querying Radiology Procedures (^RA(71))..."
    # Get count
    PROCEDURE_COUNT=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S C=0,X=0 F  S X=\$O(^RA(71,X)) Q:X=\"\"  S C=C+1 W:X=\"\" C"' 2>/dev/null | tail -1)
    
    # Get first 5 procedure names
    SAMPLE_PROCEDURES=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=0,N=0 F  S X=\$O(^RA(71,X)) Q:X=\"\"!(N>=5)  S N=N+1 W \"IEN:\",X,\" Name:\",\$P(\$G(^RA(71,X,0)),\"^\",1),\"; \""' 2>/dev/null | tail -1 | clean_m_output)

    echo "Querying Radiology Orders (^RA(75.1))..."
    # Get count
    ORDER_COUNT=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S C=0,X=0 F  S X=\$O(^RA(75.1,X)) Q:X=\"\"  S C=C+1 W:X=\"\" C"' 2>/dev/null | tail -1)
    
    # Get first 3 orders
    SAMPLE_ORDERS=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=0,N=0 F  S X=\$O(^RA(75.1,X)) Q:X=\"\"!(N>=3)  S N=N+1 W \"IEN:\",X,\" Data:\",\$E(\$G(^RA(75.1,X,0)),1,40),\"; \""' 2>/dev/null | tail -1 | clean_m_output)
fi

# Helper for JSON escaping
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
SAMPLE_PROC_ESC=$(escape_json "$SAMPLE_PROCEDURES")
SAMPLE_ORD_ESC=$(escape_json "$SAMPLE_ORDERS")

# 6. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "ground_truth": {
        "procedure_count": "$PROCEDURE_COUNT",
        "sample_procedures": "$SAMPLE_PROC_ESC",
        "order_count": "$ORDER_COUNT",
        "sample_orders": "$SAMPLE_ORD_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json