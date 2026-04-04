#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DIAGRAM_FILE="/home/ga/Diagrams/ai_argument_map.drawio"
EXPORT_FILE="/home/ga/Diagrams/exports/ai_argument_map.pdf"

# 1. Check Diagram File
if [ -f "$DIAGRAM_FILE" ]; then
    DIAGRAM_EXISTS="true"
    DIAGRAM_MTIME=$(stat -c %Y "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    if [ "$DIAGRAM_MTIME" -gt "$TASK_START" ]; then
        DIAGRAM_MODIFIED="true"
    else
        DIAGRAM_MODIFIED="false"
    fi
    # Copy to /tmp for extraction by verifier
    cp "$DIAGRAM_FILE" /tmp/final_diagram.drawio
    chmod 666 /tmp/final_diagram.drawio
else
    DIAGRAM_EXISTS="false"
    DIAGRAM_MODIFIED="false"
fi

# 2. Check PDF Export
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        EXPORT_FRESH="true"
    else
        EXPORT_FRESH="false"
    fi
else
    EXPORT_EXISTS="false"
    EXPORT_FRESH="false"
    EXPORT_SIZE="0"
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "diagram_exists": $DIAGRAM_EXISTS,
    "diagram_modified": $DIAGRAM_MODIFIED,
    "export_exists": $EXPORT_EXISTS,
    "export_fresh": $EXPORT_FRESH,
    "export_size": $EXPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json