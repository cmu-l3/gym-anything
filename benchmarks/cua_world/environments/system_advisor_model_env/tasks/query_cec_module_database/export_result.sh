#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if expected output file was created
TARGET_FILE="/home/ga/Documents/SAM_Projects/premium_modules_report.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Locate the actual CEC Modules database to provide as ground truth to the verifier
# We search for it in standard SAM installation paths
CEC_DB_PATH=$(find /opt/SAM -type f -iname "*cec*module*.csv" 2>/dev/null | head -1)

if [ -n "$CEC_DB_PATH" ] && [ -f "$CEC_DB_PATH" ]; then
    cp "$CEC_DB_PATH" /tmp/ground_truth_cec.csv
    chmod 666 /tmp/ground_truth_cec.csv
    FOUND_GROUND_TRUTH="true"
else
    FOUND_GROUND_TRUTH="false"
fi

# Check if python was used (optional signal)
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -qi "python" /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Export metadata for verifier
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "python_ran": $PYTHON_RAN,
    "found_ground_truth": $FOUND_GROUND_TRUTH,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="