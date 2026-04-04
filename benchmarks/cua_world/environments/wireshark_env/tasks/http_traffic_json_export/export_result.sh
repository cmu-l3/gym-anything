#!/bin/bash
set -e

echo "=== Exporting Task Results ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/captures/http_requests.json"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Get task start time
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Check output file status
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
# We don't verify the content here (complex logic), we just report file stats
# and make the file available for the Python verifier to pull.
cat > "$RESULT_JSON" <<EOF
{
    "output_exists": $FILE_EXISTS,
    "output_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions for copy_from_env
chmod 644 "$RESULT_JSON"
if [ -f "$OUTPUT_FILE" ]; then
    chmod 644 "$OUTPUT_FILE"
fi
if [ -f "/tmp/ground_truth.json" ]; then
    chmod 644 "/tmp/ground_truth.json"
fi

echo "Export summary saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="