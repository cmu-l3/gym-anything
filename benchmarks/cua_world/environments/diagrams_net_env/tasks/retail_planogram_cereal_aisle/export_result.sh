#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIAGRAM_FILE="/home/ga/Diagrams/planogram_template.drawio"
PDF_FILE="/home/ga/Diagrams/planogram_export.pdf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check files
DIAGRAM_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$DIAGRAM_FILE" ]; then
    DIAGRAM_EXISTS="true"
    MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
fi

# 3. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "diagram_exists": $DIAGRAM_EXISTS,
    "pdf_exists": $PDF_EXISTS,
    "diagram_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "diagram_path": "$DIAGRAM_FILE",
    "pdf_path": "$PDF_FILE"
}
EOF

# 4. Copy diagrams for the verifier to access via copy_from_env
# We need to make sure they are readable
chmod 644 /tmp/task_result.json "$DIAGRAM_FILE" "$PDF_FILE" 2>/dev/null || true

echo "=== Export Complete ==="