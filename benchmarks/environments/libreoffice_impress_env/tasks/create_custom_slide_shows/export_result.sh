#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PRES_PATH="/home/ga/Documents/Presentations/renewable_energy_strategy.odp"

# Check if output file exists
if [ -f "$PRES_PATH" ]; then
    FILE_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$PRES_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$PRES_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        # Fallback: check md5
        CURRENT_HASH=$(md5sum "$PRES_PATH" | awk '{print $1}')
        INITIAL_HASH_LINE=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "none")
        INITIAL_HASH=$(echo "$INITIAL_HASH_LINE" | awk '{print $1}')
        
        if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
            FILE_MODIFIED="true"
        else
            FILE_MODIFIED="false"
        fi
    fi
else
    FILE_EXISTS="false"
    FILE_MODIFIED="false"
    OUTPUT_SIZE="0"
fi

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size_bytes": $OUTPUT_SIZE,
    "presentation_path": "$PRES_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="