#!/bin/bash
echo "=== Exporting Task Results ==="

# Paths
DIAGRAM_FILE="/home/ga/Diagrams/telescope_schematic.drawio"
PDF_FILE="/home/ga/Diagrams/exports/telescope_ray_diagram.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
DIAGRAM_EXISTS="false"
DIAGRAM_MODIFIED="false"
PDF_EXISTS="false"

if [ -f "$DIAGRAM_FILE" ]; then
    DIAGRAM_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        DIAGRAM_MODIFIED="true"
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
fi

# 3. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "diagram_exists": $DIAGRAM_EXISTS,
    "diagram_modified": $DIAGRAM_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png",
    "diagram_path": "$DIAGRAM_FILE",
    "pdf_path": "$PDF_FILE"
}
EOF

# 4. Ensure Permissions for Copying
chmod 644 /tmp/task_result.json
if [ -f "$DIAGRAM_FILE" ]; then
    cp "$DIAGRAM_FILE" /tmp/final_diagram.drawio
    chmod 644 /tmp/final_diagram.drawio
fi

echo "Results exported to /tmp/task_result.json"