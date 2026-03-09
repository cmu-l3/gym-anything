#!/bin/bash
# export_result.sh - Post-task data export for nfpa_rating_compilation

echo "=== Exporting NFPA Rating Compilation Results ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather file statistics
REPORT_FILE="/home/ga/Desktop/nfpa_report.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
NOW=$(date +%s)

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Create JSON result
# Note: Content analysis happens in Python verifier, we just export metadata here
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "created_during_task": $CREATED_DURING_TASK,
    "report_path": "$REPORT_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="