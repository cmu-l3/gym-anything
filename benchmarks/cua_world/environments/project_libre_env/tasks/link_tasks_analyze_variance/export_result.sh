#!/bin/bash
echo "=== Exporting task results ==="

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUTPUT_XML="/home/ga/Projects/linked_variance_project.xml"
REPORT_TXT="/home/ga/Projects/variance_report.txt"

# Check XML output
if [ -f "$OUTPUT_XML" ]; then
    XML_EXISTS="true"
    XML_MTIME=$(stat -c %Y "$OUTPUT_XML" 2>/dev/null || echo "0")
    if [ "$XML_MTIME" -gt "$TASK_START" ]; then
        XML_CREATED_DURING_TASK="true"
    else
        XML_CREATED_DURING_TASK="false"
    fi
else
    XML_EXISTS="false"
    XML_CREATED_DURING_TASK="false"
fi

# Check Report output
if [ -f "$REPORT_TXT" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_TXT" 2>/dev/null || echo "0")
    # Read content
    REPORT_CONTENT=$(cat "$REPORT_TXT" | head -n 1)
else
    REPORT_EXISTS="false"
    REPORT_CONTENT=""
fi

# App status
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "xml_exists": $XML_EXISTS,
    "xml_created_during_task": $XML_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g')",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="