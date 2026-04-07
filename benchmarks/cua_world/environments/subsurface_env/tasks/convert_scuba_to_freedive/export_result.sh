#!/bin/bash
set -euo pipefail
echo "=== Exporting convert_scuba_to_freedive result ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if output file was modified during task
OUTPUT_PATH="/home/ga/Documents/dives.ssrf"
OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Create export JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_mtime": $OUTPUT_MTIME,
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Use safe permission handling for the verifier
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="