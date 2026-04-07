#!/bin/bash
echo "=== Exporting RF Link Drop Gap Detection Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/gap_report.json"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# Read the hidden actual drop duration (written by the simulator script)
ACTUAL_DROP="0.0"
if [ -f "/tmp/actual_drop_duration.txt" ]; then
    ACTUAL_DROP=$(cat /tmp/actual_drop_duration.txt | tr -d '[:space:]')
fi

# Take final screenshot
take_screenshot /tmp/rf_link_drop_end.png

cat > /tmp/rf_link_drop_gap_detection_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "actual_drop_duration": $ACTUAL_DROP
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "Actual drop duration generated: $ACTUAL_DROP"
echo "=== Export Complete ==="