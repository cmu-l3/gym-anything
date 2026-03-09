#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Format Financial Table Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Wait for file modification
OUTPUT_PATH="/home/ga/Documents/Presentations/Q4_Financials.odp"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    FILE_MODIFIED="false"
fi

# Close Impress (Ctrl+Q)
echo "Closing Impress..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="