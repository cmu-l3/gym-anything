#!/bin/bash
# Export script for Audit Lab Topography task

echo "=== Exporting Audit Lab Topography Result ==="

# 1. capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# 2. Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check VistA status
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
fi

# 4. Check Browser Window Title (for simple heuristic verification)
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
GLOBAL_VIEWER_OPEN="false"
if echo "$BROWSER_TITLE" | grep -qi "global"; then
    GLOBAL_VIEWER_OPEN="true"
fi

# 5. Get Ground Truth (Sample of ^LAB(61) to compare against visual)
# This query gets the first 10 entries from Topography Field
SAMPLE_DATA=""
if [ "$VISTA_STATUS" = "running" ]; then
    SAMPLE_DATA=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S U=\"^\",X=0,N=0 F  S X=\$O(^LAB(61,X)) Q:X=\"\"!(N>=5)  S N=N+1 W \$P(\$G(^LAB(61,X,0)),U,1),\", \""' 2>/dev/null)
fi

# Escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}
BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")
SAMPLE_DATA_ESC=$(escape_json "$SAMPLE_DATA")

# 6. Create Result JSON
cat > /tmp/audit_lab_topography_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "global_viewer_open": $GLOBAL_VIEWER_OPEN,
    "ground_truth_sample": "$SAMPLE_DATA_ESC",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "Result JSON saved to /tmp/audit_lab_topography_result.json"