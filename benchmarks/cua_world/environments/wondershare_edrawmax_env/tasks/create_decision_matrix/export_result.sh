#!/bin/bash
echo "=== Exporting create_decision_matrix results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EDDX_PATH="/home/ga/Documents/db_evaluation_matrix.eddx"
PDF_PATH="/home/ga/Documents/db_evaluation_matrix.pdf"

# Check EDDX file
if [ -f "$EDDX_PATH" ]; then
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED="true"
    else
        EDDX_CREATED="false"
    fi
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
else
    EDDX_EXISTS="false"
    EDDX_CREATED="false"
    EDDX_SIZE="0"
fi

# Check PDF file
if [ -f "$PDF_PATH" ]; then
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED="true"
    else
        PDF_CREATED="false"
    fi
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
else
    PDF_EXISTS="false"
    PDF_CREATED="false"
    PDF_SIZE="0"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_created_during_task": $EDDX_CREATED,
    "eddx_size_bytes": $EDDX_SIZE,
    "pdf_exists": $PDF_EXISTS,
    "pdf_created_during_task": $PDF_CREATED,
    "pdf_size_bytes": $PDF_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="