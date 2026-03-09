#!/bin/bash
echo "=== Exporting NSF Grant Narrative Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot (CRITICAL EVIDENCE)
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_FILE="/home/ga/Documents/NSF_SES2415837_ProjectDescription.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if OpenOffice is still running
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create result JSON for verifier
# We only export metadata here. The heavy parsing of the ODT file 
# happens in the verifier.py which copies the file to the host.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running_at_end": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="