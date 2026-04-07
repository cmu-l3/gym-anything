#!/bin/bash
set -e
echo "=== Exporting task result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare basic info export
LOAN_FILE="/home/ga/Documents/loan_amortization.xlsx"
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_SIZE="0"
CURRENT_HASH=""

if [ -f "$LOAN_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$LOAN_FILE")
    FILE_SIZE=$(stat -c %s "$LOAN_FILE")
    CURRENT_HASH=$(md5sum "$LOAN_FILE" | awk '{print $1}')
fi

# Load start variables
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")

# Write to JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "file_size": $FILE_SIZE,
    "task_start_time": $START_TIME,
    "initial_hash": "$INITIAL_HASH",
    "current_hash": "$CURRENT_HASH"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="