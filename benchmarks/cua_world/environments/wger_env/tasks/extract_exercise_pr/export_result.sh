#!/bin/bash
set -e
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/squat_pr.txt"
GROUND_TRUTH=$(cat /tmp/.pr_truth 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_CONTENT='""'

# Check if the agent created the output file and extract its content securely
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    # Read the first line, strip whitespace, and safely JSON encode it
    FILE_CONTENT=$(head -n 1 "$OUTPUT_FILE" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read().strip()))')
fi

# Take final screenshot for visual evidence
take_screenshot /tmp/task_final.png

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_content": $FILE_CONTENT,
    "ground_truth": "$GROUND_TRUTH",
    "task_start": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move into place and apply correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="