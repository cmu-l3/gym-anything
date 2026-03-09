#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/Presentations/employee_handbook_nav.odp"

# 1. Attempt to save if the user hasn't (Ctrl+S)
# Note: User instructions say "Save as...", so we check if file exists. 
# If not, we try to save blindly just in case they forgot the final step.
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Output file not found, checking for default save..."
    # If they just hit Ctrl+S, it might be in the original file
    ORIGINAL_FILE="/home/ga/Documents/Presentations/employee_handbook.odp"
    if [ -f "$ORIGINAL_FILE" ]; then
        # Check if original was modified
        MOD_TIME=$(stat -c %Y "$ORIGINAL_FILE")
        if [ "$MOD_TIME" -gt "$TASK_START" ]; then
            echo "Original file was modified, copying to expected output for verification..."
            cp "$ORIGINAL_FILE" "$OUTPUT_FILE"
        fi
    fi
fi

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Generate Result JSON
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy the ODP file to tmp for the verifier to access easily via copy_from_env
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_FILE" /tmp/verification_target.odp
    chmod 666 /tmp/verification_target.odp
fi

echo "=== Export Complete ==="