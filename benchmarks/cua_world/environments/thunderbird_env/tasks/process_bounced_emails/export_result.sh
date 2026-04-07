#!/bin/bash
set -euo pipefail

echo "=== Exporting Process Bounced Emails Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check the exported text file
TEXT_FILE="/home/ga/Desktop/bounced_contacts.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME=0

if [ -f "$TEXT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    # Read the content, escaping for JSON
    FILE_CONTENT=$(cat "$TEXT_FILE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])" 2>/dev/null || echo "")
fi

# Determine if the file was created/modified during the task
FILE_CREATED_DURING_TASK="false"
if [ "$FILE_EXISTS" = "true" ] && [ "$FILE_MTIME" -ge "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# Ensure all thunderbird data is flushed to disk before verifier copies it
sleep 2

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "text_file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": "$FILE_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="