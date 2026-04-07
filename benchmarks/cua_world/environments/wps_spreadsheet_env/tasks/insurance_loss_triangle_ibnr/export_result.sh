#!/bin/bash
echo "=== Exporting insurance_loss_triangle_ibnr results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check expected output file (Save As target)
OUTPUT_PATH="/home/ga/Documents/loss_reserve_analysis.xlsx"

# Also check if agent saved to the original file or common variants
FOUND_PATH=""
if [ -f "$OUTPUT_PATH" ]; then
    FOUND_PATH="$OUTPUT_PATH"
else
    for candidate in \
        "/home/ga/Documents/claims_data.xlsx" \
        "/home/ga/Documents/loss_reserve.xlsx" \
        "/home/ga/Documents/reserve_analysis.xlsx"; do
        if [ -f "$candidate" ]; then
            FOUND_PATH="$candidate"
            break
        fi
    done
fi

if [ -n "$FOUND_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$FOUND_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$FOUND_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED="false"
    OUTPUT_SIZE="0"
    FOUND_PATH=""
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "et" > /dev/null && echo "true" || echo "false")

# Write basic JSON using pure bash (matching existing task patterns)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "found_path": "$FOUND_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
