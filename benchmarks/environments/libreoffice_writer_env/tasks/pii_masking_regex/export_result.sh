#!/bin/bash
set -e

echo "=== Exporting PII Masking Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Constants
OUTPUT_FILE="/home/ga/Documents/roster_sanitized.odt"
TASK_START_FILE="/tmp/task_start_time.txt"

# Capture final state
take_screenshot /tmp/task_final.png

# Check if output file exists
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    
    # Check timestamp against task start
    TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Capture Writer state (running or not)
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
    
    # Close Writer gracefully
    wid=$(get_writer_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        safe_xdotool ga :1 key ctrl+q
        sleep 1
        # Handle "Save changes?" - Don't save (agent should have saved)
        safe_xdotool ga :1 key alt+d 2>/dev/null || true
    fi
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

# Copy ground truth to tmp for verifier (verifier runs in host but needs access)
# Note: In this framework, verifier.py runs on host and uses copy_from_env.
# We don't need to copy ground truth inside the container, but we need to ensure
# the verifier can access the ground truth if it was inside. 
# Actually, the ground truth was created at /var/lib/task_data/roster_ground_truth.json
# We should copy it to a readable tmp location so verifier.py can pull it via copy_from_env
cp /var/lib/task_data/roster_ground_truth.json /tmp/roster_ground_truth.json
chmod 644 /tmp/roster_ground_truth.json

echo "Export complete. Result saved to /tmp/task_result.json"