#!/bin/bash
echo "=== Exporting SEO Sitemap Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DRAWIO_PATH="/home/ga/Diagrams/sitemap_architecture.drawio"
PDF_PATH="/home/ga/Diagrams/exports/sitemap.pdf"

# Check artifacts
DRAWIO_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$DRAWIO_PATH" ]; then
    DRAWIO_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
fi

# Check if app running
APP_RUNNING=$(pgrep -f "drawio" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON
# We don't parse XML here to keep shell script simple. We rely on verifier.py reading the file.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_exists": $DRAWIO_EXISTS,
    "pdf_exists": $PDF_EXISTS,
    "file_created_during_task": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"