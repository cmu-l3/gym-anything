#!/bin/bash
echo "=== Exporting SysML CubeSat BDD Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Diagrams/aurora3_bdd.drawio"
PDF_FILE="/home/ga/Diagrams/aurora3_bdd.pdf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check .drawio file
DRAWIO_EXISTS="false"
DRAWIO_MODIFIED="false"
DRAWIO_SIZE="0"
if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    DRAWIO_SIZE=$(stat -c %s "$DRAWIO_FILE")
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DRAWIO_MODIFIED="true"
    fi
fi

# Check .pdf file
PDF_EXISTS="false"
PDF_MODIFIED="false"
if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    MTIME=$(stat -c %Y "$PDF_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PDF_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_modified": $DRAWIO_MODIFIED,
    "drawio_size": $DRAWIO_SIZE,
    "pdf_exists": $PDF_EXISTS,
    "pdf_modified": $PDF_MODIFIED,
    "drawio_path": "$DRAWIO_FILE",
    "pdf_path": "$PDF_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"