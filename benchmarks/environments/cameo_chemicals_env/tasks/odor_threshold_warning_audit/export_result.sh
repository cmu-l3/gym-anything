#!/bin/bash
# export_result.sh - Export results for Odor Warning Property Safety Audit

echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (Evidence of final state)
take_screenshot /tmp/task_final.png

# 2. Get File Stats
OUTPUT_FILE="/home/ga/Documents/odor_safety_audit.csv"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_EXISTS=false
FILE_SIZE=0
FILE_CREATED_DURING_TASK=false

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# 3. Create JSON Result
# We do not read the CSV content here; the verifier will pull the file using copy_from_env
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"