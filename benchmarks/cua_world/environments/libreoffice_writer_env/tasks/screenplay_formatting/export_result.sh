#!/bin/bash
# export_result.sh - Screenplay Formatting Task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Screenplay Formatting Results ==="

# 1. Capture final screenshot (CRITICAL for VLM verification)
take_screenshot /tmp/task_final.png

# 2. Check if output file exists
OUTPUT_PATH="/home/ga/Documents/screenplay_formatted.docx"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    
    # Check modification time against task start time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Create JSON result
# We create a temp file and move it to avoid permission issues
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

# 4. Gracefully close Writer (optional but good hygiene)
# We don't force kill immediately to allow for final state observation if needed
# But for export we generally just leave it or soft close.
# Here we'll just log that we are done.

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="