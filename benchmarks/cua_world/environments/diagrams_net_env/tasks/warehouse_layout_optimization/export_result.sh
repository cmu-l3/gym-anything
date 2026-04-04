#!/bin/bash
echo "=== Exporting Warehouse Layout Results ==="

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
DIAGRAM_FILE="/home/ga/Diagrams/warehouse_current.drawio"
PDF_FILE="/home/ga/Diagrams/exports/optimized_layout.pdf"

# 1. Check Files
DIAGRAM_EXISTS="false"
DIAGRAM_MODIFIED="false"
PDF_EXISTS="false"

if [ -f "$DIAGRAM_FILE" ]; then
    DIAGRAM_EXISTS="true"
    # Check modification time
    M_TIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$M_TIME" -gt "$TASK_START" ]; then
        DIAGRAM_MODIFIED="true"
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
fi

# 2. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create JSON Result
# We do not parse the XML here to avoid complex bash/python deps in the export script.
# We will rely on the verifier to pull the actual .drawio file out and parse it robustly.
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "diagram_exists": $DIAGRAM_EXISTS,
    "diagram_modified": $DIAGRAM_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "diagram_path": "$DIAGRAM_FILE",
    "pdf_path": "$PDF_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"