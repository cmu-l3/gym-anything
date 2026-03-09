#!/bin/bash
# export_result.sh - Clinical Protocol Formatting

source /workspace/scripts/task_utils.sh

echo "=== Exporting Clinical Protocol Formatting Result ==="

# 1. Capture final screenshot (CRITICAL evidence)
take_screenshot /tmp/task_final.png

# 2. Define paths
OUTPUT_FILE="/home/ga/Documents/sepsis_protocol_formatted.docx"
START_TIME_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# 3. Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check if LibreOffice is still running
APP_RUNNING="false"
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON result
# We do NOT analyze the DOCX content here; we pass the file to the verifier (Python)
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "output_path": "$OUTPUT_FILE",
    "timestamp": $(date +%s)
}
EOF

# 6. Safe copy to /tmp for easy extraction by verifier if needed
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$OUTPUT_FILE" /tmp/sepsis_protocol_formatted.docx
    chmod 666 /tmp/sepsis_protocol_formatted.docx
fi

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="