#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Architecture Diagram Result ==="

# 1. Save the file via Ctrl+S (with timeout to prevent hangs)
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 1
    echo "Sending Save command..."
    # Use timeout to prevent su/xdotool from hanging in SSH contexts
    timeout 10 su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" 2>/dev/null || true
    sleep 3
    # Dismiss any format dialog (Keep Current Format)
    timeout 5 su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
    sleep 2
fi

# 2. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")

# 3. Check file state
FILE_PATH="/home/ga/Documents/Presentations/platform_architecture.odp"
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE=0

if [ -f "$FILE_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || echo "0")

    # Check modification via mtime comparison
    CURRENT_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi

    # Double-check via hash comparison
    if [ "$FILE_MODIFIED" = "false" ]; then
        CURRENT_HASH=$(md5sum "$FILE_PATH" 2>/dev/null | awk '{print $1}')
        INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")
        if [ "$CURRENT_HASH" != "$INITIAL_HASH" ] && [ -n "$INITIAL_HASH" ]; then
            FILE_MODIFIED="true"
        fi
    fi
fi

# 4. Take final screenshot (try multiple methods, non-fatal)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null \
    || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null \
    || true

# 5. Write result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$FILE_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
