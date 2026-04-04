#!/bin/bash
echo "=== Exporting SWOT Analysis Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")

FILE_PATH="/home/ga/Documents/Presentations/renewable_energy_strategy.odp"

# Check file status
if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after start
    if [ "$FILE_MTIME" -gt "$TASK_START" ] && [ "$FILE_MTIME" -ne "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MODIFIED="false"
fi

# Save (Ctrl+S) and Close (Ctrl+Q) gracefully to ensure edits are written
# We do this only if the agent didn't close it, to ensure we capture the latest state
if pgrep -f "soffice.bin" > /dev/null; then
    echo "Saving and closing Impress..."
    WID=$(get_impress_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        safe_xdotool ga :1 key ctrl+s
        sleep 2
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "file_path": "$FILE_PATH"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="