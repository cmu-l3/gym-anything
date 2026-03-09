#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIAGRAM_PATH="/home/ga/Diagrams/hospital_strategy_map.drawio"
PDF_PATH="/home/ga/Diagrams/hospital_strategy_map.pdf"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
DIAGRAM_EXISTS="false"
DIAGRAM_MODIFIED="false"
DIAGRAM_SIZE=0
if [ -f "$DIAGRAM_PATH" ]; then
    DIAGRAM_EXISTS="true"
    DIAGRAM_MTIME=$(stat -c %Y "$DIAGRAM_PATH" 2>/dev/null || echo "0")
    DIAGRAM_SIZE=$(stat -c %s "$DIAGRAM_PATH" 2>/dev/null || echo "0")
    if [ "$DIAGRAM_MTIME" -gt "$TASK_START" ]; then
        DIAGRAM_MODIFIED="true"
    fi
fi

PDF_EXISTS="false"
PDF_SIZE=0
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
fi

# 3. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "diagram_exists": $DIAGRAM_EXISTS,
    "diagram_modified": $DIAGRAM_MODIFIED,
    "diagram_size": $DIAGRAM_SIZE,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE
}
EOF

# Ensure permissions for copy_from_env
chmod 644 /tmp/task_result.json
if [ -f "$DIAGRAM_PATH" ]; then chmod 644 "$DIAGRAM_PATH"; fi
if [ -f "$PDF_PATH" ]; then chmod 644 "$PDF_PATH"; fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json