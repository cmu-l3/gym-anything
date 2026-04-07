#!/bin/bash
# Export script for Review Surgery Cases task
# Captures state and queries VistA for ground truth comparison

echo "=== Exporting Review Surgery Cases Result ==="

# 1. Capture Final Screenshot (Evidence)
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot saved."

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Infrastructure Status
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
[ -n "$BROWSER_TITLE" ] && BROWSER_OPEN="true"

# 5. Extract Ground Truth Data from VistA (Backend Query)
# We pull a few surgery cases to verify they actually exist and what they look like.
# This helps the verifier know if "APPENDICITIS" or similar terms SHOULD appear.
SURGERY_DATA_EXISTS="false"
SAMPLE_CASES=""

if [ "$VISTA_STATUS" = "running" ]; then
    # Check if any cases exist
    FIRST_IEN=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^SRF(0))"' 2>/dev/null | tail -1)
    
    if [ -n "$FIRST_IEN" ]; then
        SURGERY_DATA_EXISTS="true"
        
        # Extract first 5 cases with Procedure Name (OP node)
        # M Code: Loop 5 times, get ^SRF(DA,"OP") or ^SRF(DA,0)
        M_CMD='S U="^",DA=0,C=0 F  S DA=$O(^SRF(DA)) Q:DA=""!(C>=5)  S C=C+1 W "IEN:",DA," OP:",$G(^SRF(DA,"OP"))," | " '
        
        # Escape for bash
        SAMPLE_CASES=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD '$M_CMD'" 2>/dev/null | tail -1)
    fi
fi

# 6. Escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g'
}

BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
SAMPLE_CASES_ESC=$(escape_json "$SAMPLE_CASES")

# 7. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_open": $BROWSER_OPEN,
    "browser_title": "$BROWSER_TITLE_ESC",
    "ground_truth": {
        "data_exists": $SURGERY_DATA_EXISTS,
        "sample_data": "$SAMPLE_CASES_ESC"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "Result JSON created at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="