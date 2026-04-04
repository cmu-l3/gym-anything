#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities (if available, otherwise rely on local commands)
# source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Diagrams/cnn_architecture.drawio"
PDF_FILE="/home/ga/Diagrams/cnn_architecture.pdf"

# 1. Take final screenshot (Evidence of work)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence and Timestamps
DRAWIO_EXISTS="false"
PDF_EXISTS="false"
DRAWIO_SIZE="0"
DRAWIO_MODIFIED="false"

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    DRAWIO_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_TIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        DRAWIO_MODIFIED="true"
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$PDF_FILE")
    # PDF should also be new
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        PDF_MODIFIED="true"
    fi
fi

# 3. Create Result JSON
# We don't do deep XML parsing here (bash/python dependency risk inside container).
# We delegate that to the host verifier.py which will copy the file out.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_size": $DRAWIO_SIZE,
    "drawio_modified_during_task": $DRAWIO_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="