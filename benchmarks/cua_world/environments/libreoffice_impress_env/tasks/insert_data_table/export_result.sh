#!/bin/bash
echo "=== Exporting insert_data_table results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")

PRES_DIR="/home/ga/Documents/Presentations"
PPTX_FILE="$PRES_DIR/renewable_energy_report.pptx"
ODP_FILE="$PRES_DIR/renewable_energy_report.odp"

# Determine which file holds the result (users might save as ODP or PPTX)
RESULT_FILE=""
FILE_FORMAT=""

# Check if PPTX was modified
if [ -f "$PPTX_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$PPTX_FILE")
    CURRENT_HASH=$(md5sum "$PPTX_FILE")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        RESULT_FILE="$PPTX_FILE"
        FILE_FORMAT="pptx"
    fi
fi

# If PPTX wasn't modified/saved, check if ODP was created
if [ -z "$RESULT_FILE" ] && [ -f "$ODP_FILE" ]; then
    ODP_MTIME=$(stat -c %Y "$ODP_FILE")
    if [ "$ODP_MTIME" -gt "$TASK_START" ]; then
        RESULT_FILE="$ODP_FILE"
        FILE_FORMAT="odp"
    fi
fi

# If we found a result file, gather stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
FILE_PATH=""

if [ -n "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MODIFIED="true" # By definition of how we selected it above
    FILE_SIZE=$(stat -c %s "$RESULT_FILE")
    FILE_PATH="$RESULT_FILE"
    echo "Found result file: $RESULT_FILE ($FILE_FORMAT)"
else
    # Fallback: just report on the original file
    echo "No modified result file found. Checking original path."
    if [ -f "$PPTX_FILE" ]; then
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c %s "$PPTX_FILE")
        FILE_PATH="$PPTX_FILE"
        # Double check modification logic
        CUR_MTIME=$(stat -c %Y "$PPTX_FILE")
        if [ "$CUR_MTIME" -gt "$TASK_START" ]; then
            FILE_MODIFIED="true"
        fi
        FILE_FORMAT="pptx"
    fi
fi

# Check if Impress is still running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_path": "$FILE_PATH",
    "file_format": "$FILE_FORMAT",
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="