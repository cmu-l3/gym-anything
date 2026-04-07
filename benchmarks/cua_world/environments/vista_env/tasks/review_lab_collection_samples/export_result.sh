#!/bin/bash
# Export script for Review Lab Collection Samples task

echo "=== Exporting Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Function to escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true
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

# Check Browser Title (Indicator of what is open)
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 | cut -d' ' -f5- || echo "")
BROWSER_OPEN="false"
if [ -n "$BROWSER_TITLE" ]; then
    BROWSER_OPEN="true"
fi

# Check if browser title indicates navigation to ^LAB or Collection Sample
GLOBAL_ACCESSED="false"
if echo "$BROWSER_TITLE" | grep -qiE "LAB|62|Collection"; then
    GLOBAL_ACCESSED="true"
fi

# Load Ground Truth (prepared in setup)
GROUND_TRUTH_SAMPLES="[]"
if [ -f /tmp/ground_truth_samples.json ]; then
    GROUND_TRUTH_SAMPLES=$(cat /tmp/ground_truth_samples.json)
fi

# Prepare result JSON
BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")

cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "title_indicates_global": $GLOBAL_ACCESSED,
    "ground_truth_samples": $GROUND_TRUTH_SAMPLES,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result JSON content:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="