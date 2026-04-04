#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPECTED_OUTPUT="/home/ga/Documents/Presentations/board_meeting_branded.odp"
FALLBACK_OUTPUT_PPTX="/home/ga/Documents/Presentations/board_meeting_branded.pptx"
ORIGINAL_FILE="/home/ga/Documents/Presentations/board_meeting.pptx"

# Determine which file to check
FINAL_FILE=""
FILE_FORMAT=""

if [ -f "$EXPECTED_OUTPUT" ]; then
    FINAL_FILE="$EXPECTED_OUTPUT"
    FILE_FORMAT="odp"
elif [ -f "$FALLBACK_OUTPUT_PPTX" ]; then
    FINAL_FILE="$FALLBACK_OUTPUT_PPTX"
    FILE_FORMAT="pptx"
elif [ -f "$ORIGINAL_FILE" ]; then
    # Check if original file was modified
    ORIG_MTIME=$(stat -c %Y "$ORIGINAL_FILE" 2>/dev/null || echo "0")
    if [ "$ORIG_MTIME" -gt "$TASK_START" ]; then
        FINAL_FILE="$ORIGINAL_FILE"
        FILE_FORMAT="pptx" # Likely still pptx if they just hit save
    fi
fi

# Gather file statistics
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -n "$FINAL_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$FINAL_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$FINAL_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Impress is still running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "final_file_path": "$FINAL_FILE",
    "file_format": "$FILE_FORMAT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result JSON safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy the presentation file to temp for extraction by verifier
if [ -n "$FINAL_FILE" ]; then
    cp "$FINAL_FILE" /tmp/submission_file.dat
    chmod 666 /tmp/submission_file.dat
fi

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="