#!/bin/bash
echo "=== Exporting Telemetry Conversion Verification Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/telemetry_conversion_verification_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/conversion_verification.json"

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

# Take final screenshot
DISPLAY=:1 import -window root /tmp/telemetry_conversion_verification_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/telemetry_conversion_verification_end.png 2>/dev/null || true

cat > /tmp/telemetry_conversion_verification_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="