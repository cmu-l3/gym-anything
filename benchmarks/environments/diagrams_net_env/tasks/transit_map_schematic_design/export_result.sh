#!/bin/bash
echo "=== Exporting Transit Map Task Results ==="

# 1. Timestamps & Basic Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DIAGRAM_PATH="/home/ga/Diagrams/metro_system_map.drawio"
PDF_PATH="/home/ga/Diagrams/exports/metro_map_v2.pdf"

FILE_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"
PDF_SIZE="0"

if [ -f "$DIAGRAM_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    # Copy diagram to temp for verifier to access easily
    cp "$DIAGRAM_PATH" /tmp/final_diagram.drawio
    chmod 666 /tmp/final_diagram.drawio
fi

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
    # Copy PDF for verification if needed
    cp "$PDF_PATH" /tmp/final_export.pdf
    chmod 666 /tmp/final_export.pdf
fi

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "diagram_exists": $FILE_EXISTS,
    "diagram_modified": $FILE_MODIFIED,
    "pdf_exported": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete. Data ready in /tmp/task_result.json, /tmp/final_diagram.drawio, /tmp/final_export.pdf"