#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Result ==="

ODP_FILE="/home/ga/Documents/Presentations/quarterly_review.odp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ensure file is saved
echo "Ensuring file is saved..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 3
    # Close application
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Gather file stats
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ -f "$ODP_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ODP_FILE")
    FILE_MTIME=$(stat -c %Y "$ODP_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Copy ODP to temp for verifier (preserving permissions)
cp "$ODP_FILE" /tmp/result_presentation.odp 2>/dev/null || true
chmod 666 /tmp/result_presentation.odp 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."