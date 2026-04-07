#!/bin/bash
set -e
echo "=== Exporting duplicate_dive_and_adjust_time task result ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SSRF_PATH="/home/ga/Documents/dives.ssrf"

if [ -f "$SSRF_PATH" ]; then
    SSRF_EXISTS="true"
    SSRF_MTIME=$(stat -c %Y "$SSRF_PATH" 2>/dev/null || echo "0")
    SSRF_SIZE=$(stat -c %s "$SSRF_PATH" 2>/dev/null || echo "0")
    
    if [ "$SSRF_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    else
        FILE_MODIFIED_DURING_TASK="false"
    fi
else
    SSRF_EXISTS="false"
    SSRF_MTIME="0"
    SSRF_SIZE="0"
    FILE_MODIFIED_DURING_TASK="false"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ssrf_exists": $SSRF_EXISTS,
    "ssrf_mtime": $SSRF_MTIME,
    "ssrf_size_bytes": $SSRF_SIZE,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="