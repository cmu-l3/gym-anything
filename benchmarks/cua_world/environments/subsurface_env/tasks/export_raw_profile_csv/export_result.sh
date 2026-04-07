#!/bin/bash
set -euo pipefail
echo "=== Exporting export_raw_profile_csv task result ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/dive3_profile.csv"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Verify file was generated after setup completed
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Capture final UI state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Save local metadata for fast top-level checking
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK
}
EOF

# Make result available to host verifier
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="