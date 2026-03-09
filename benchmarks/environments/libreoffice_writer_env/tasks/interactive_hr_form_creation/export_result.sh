#!/bin/bash
set -euo pipefail

echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/onboarding_form_interactive.odt"

# Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Capture final screenshot
echo "Capturing final screenshot..."
focus_window "$(get_writer_window_id)" || true
sleep 0.5
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result JSON safely
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

# Attempt to save changes if user forgot (optional helper for verification context, 
# though stricter tasks might require user to save)
# We won't force save here to strictly test if the agent saved the file.

# Close LibreOffice
echo "Closing LibreOffice..."
pkill -f soffice || true

echo "=== Export complete ==="