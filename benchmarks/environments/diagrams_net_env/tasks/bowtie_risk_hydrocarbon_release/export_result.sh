#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DRAWIO_FILE="/home/ga/Diagrams/bowtie_hydrocarbon_release.drawio"
PDF_FILE="/home/ga/Diagrams/bowtie_hydrocarbon_release.pdf"

# Check .drawio file
if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    DRAWIO_SIZE=$(stat -c %s "$DRAWIO_FILE")
    DRAWIO_MTIME=$(stat -c %Y "$DRAWIO_FILE")
else
    DRAWIO_EXISTS="false"
    DRAWIO_SIZE="0"
    DRAWIO_MTIME="0"
fi

# Check .pdf file
if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_FILE")
    PDF_MTIME=$(stat -c %Y "$PDF_FILE")
else
    PDF_EXISTS="false"
    PDF_SIZE="0"
    PDF_MTIME="0"
fi

# Determine if file was modified during task
FILE_MODIFIED="false"
if [ "$DRAWIO_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_size": $DRAWIO_SIZE,
    "drawio_mtime": $DRAWIO_MTIME,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "file_modified_during_task": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"