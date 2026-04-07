#!/bin/bash
set -euo pipefail

echo "=== Exporting rename_dive_computer task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/ssrf_initial_hash.txt 2>/dev/null || echo "")

OUTPUT_PATH="/home/ga/Documents/dives.ssrf"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
    
    CURRENT_HASH=$(sha256sum "$OUTPUT_PATH" | awk '{print $1}')
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        CONTENT_CHANGED="true"
    else
        CONTENT_CHANGED="false"
    fi
    OUTPUT_EXISTS="true"
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED="false"
    CONTENT_CHANGED="false"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Export metadata to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "content_changed": $CONTENT_CHANGED
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="