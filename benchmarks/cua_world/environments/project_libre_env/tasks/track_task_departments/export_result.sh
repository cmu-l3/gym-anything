#!/bin/bash
echo "=== Exporting task results ==="

# 1. Record basic task info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Projects/department_tagged.xml"

# 2. Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Anti-gaming: File must be modified AFTER task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_VALID_TIME="true"
    else
        FILE_VALID_TIME="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_VALID_TIME="false"
fi

# 3. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. JSON Report
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "file_valid_time": $FILE_VALID_TIME,
    "output_path": "$OUTPUT_PATH"
}
EOF

# 5. Set permissions for the python verifier to read
chmod 644 /tmp/task_result.json
if [ -f "$OUTPUT_PATH" ]; then
    chmod 644 "$OUTPUT_PATH"
fi

echo "=== Export complete ==="