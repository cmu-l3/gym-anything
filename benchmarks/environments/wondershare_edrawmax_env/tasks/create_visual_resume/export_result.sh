#!/bin/bash
echo "=== Exporting create_visual_resume results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EDDX_PATH="/home/ga/Documents/jordan_smith_resume.eddx"
PDF_PATH="/home/ga/Documents/jordan_smith_resume.pdf"

# Check EDDX file
EDDX_EXISTS="false"
EDDX_SIZE="0"
EDDX_CREATED_DURING_TASK="false"
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    if [ "$EDDX_MTIME" -ge "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    fi
fi

# Check PDF file
PDF_EXISTS="false"
PDF_SIZE="0"
PDF_CREATED_DURING_TASK="false"
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    if [ "$PDF_MTIME" -ge "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size_bytes": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING_TASK,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size_bytes": $PDF_SIZE,
    "pdf_created_during_task": $PDF_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="