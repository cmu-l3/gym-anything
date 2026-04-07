#!/bin/bash
# Export script for Audit Person Classes

echo "=== Exporting Audit Person Classes Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

# 2. Basic environment checks
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)

# Check YDBGui access
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# Check browser title
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 | cut -d' ' -f5- || echo "")

# 3. Ground Truth: Query VistA for 'Emergency Medicine' in ^USC(8932.1)
# We look for the X12 code (piece 6) where name (piece 1,2, or 3) contains 'Emergency Medicine'
echo "Querying VistA for ground truth..."
GT_QUERY_CMD='S D0=0,FOUND=0 F  S D0=$O(^USC(8932.1,D0)) Q:D0'>0  S Z=$G(^(D0,0)) I Z["Emergency Medicine" S FOUND=1 W "FOUND^"_$P(Z,"^",6)_"^"_$P(Z,"^",1)_"^"_$P(Z,"^",2)_"^"_$P(Z,"^",3),! Q'
# Escape logic for bash->docker->mumps
GT_RESULT=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD '$GT_QUERY_CMD'" 2>/dev/null | tr -d '\r')

# Parse Ground Truth
GT_FOUND="false"
GT_CODE=""
GT_NAME=""
if [[ "$GT_RESULT" == FOUND* ]]; then
    GT_FOUND="true"
    GT_CODE=$(echo "$GT_RESULT" | cut -d'^' -f2)
    GT_NAME=$(echo "$GT_RESULT" | cut -d'^' -f3-5) # Grab pieces 1-3 as name context
fi

echo "Ground Truth - Found: $GT_FOUND, Code: $GT_CODE"

# 4. JSON Export
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_title": "$BROWSER_TITLE",
    "ground_truth": {
        "found": $GT_FOUND,
        "x12_code": "$GT_CODE",
        "name_context": "$GT_NAME"
    },
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "Result exported to /tmp/task_result.json"