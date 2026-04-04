#!/bin/bash
echo "=== Exporting Rack Elevation Audit Results ==="

# 1. Basic File Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIAGRAM_FILE="/home/ga/Diagrams/rack_a07.drawio"
PDF_FILE="/home/ga/Diagrams/exports/rack_a07_audit.pdf"

# Check diagram modification
if [ -f "$DIAGRAM_FILE" ]; then
    DIAGRAM_MTIME=$(stat -c %Y "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    if [ "$DIAGRAM_MTIME" -gt "$TASK_START" ]; then
        DIAGRAM_MODIFIED="true"
    else
        DIAGRAM_MODIFIED="false"
    fi
    DIAGRAM_SIZE=$(stat -c %s "$DIAGRAM_FILE" 2>/dev/null || echo "0")
else
    DIAGRAM_MODIFIED="false"
    DIAGRAM_SIZE="0"
fi

# Check PDF export
if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_FILE" 2>/dev/null || echo "0")
else
    PDF_EXISTS="false"
    PDF_SIZE="0"
fi

# 2. Application State
APP_RUNNING=$(pgrep -f "drawio" > /dev/null && echo "true" || echo "false")

# 3. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "diagram_modified": $DIAGRAM_MODIFIED,
    "diagram_size": $DIAGRAM_SIZE,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location (ensure read permissions)
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="