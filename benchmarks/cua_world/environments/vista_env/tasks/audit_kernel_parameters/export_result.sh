#!/bin/bash
# Export script for Audit Kernel Parameters task

echo "=== Exporting Audit Kernel Parameters Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type escape_json &>/dev/null; then
    escape_json() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
    }
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check VistA Status
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
fi

# Check YDBGui Access
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# Browser State
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
if [ -n "$BROWSER_TITLE" ]; then
    BROWSER_OPEN="true"
fi

# Capture Ground Truth Data for Verification
# We fetch the exact definition of ORWOR TIMEOUT CHART from the DB to compare against what VLM sees
GT_DATA=""
GT_IEN=$(cat /tmp/target_param_ien.txt 2>/dev/null)

if [ "$VISTA_STATUS" = "running" ]; then
    # If we didn't get IEN in setup, try again
    if [ -z "$GT_IEN" ]; then
         GT_IEN=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^XTV(8989.51,\"B\",\"ORWOR TIMEOUT CHART\",0))"' 2>/dev/null | tail -1)
    fi
    
    if [ -n "$GT_IEN" ] && [ "$GT_IEN" != "0" ]; then
        # Get Node 0 (Name^Type) and Node 1 (Description)
        GT_NODE0=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'W \$G(^XTV(8989.51,$GT_IEN,0))'" 2>/dev/null | tail -1)
        # Assuming description is in node 1, or just verify existence
        GT_DATA="$GT_NODE0"
    fi
fi

BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
GT_DATA_ESC=$(escape_json "$GT_DATA")

# JSON Export
cat > /tmp/audit_kernel_parameters_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "ground_truth": {
        "ien": "$GT_IEN",
        "data_node_0": "$GT_DATA_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON saved."
cat /tmp/audit_kernel_parameters_result.json