#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Cross-Reference Repair Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/functional_spec_v2.docx"

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Generate result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_PATH",
    "output_size": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to destination
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Close Writer to ensure clean state for next task (optional, but good practice)
# We use safe exit via menu shortcut or wmctrl close, avoiding kill if possible
if pgrep -f "soffice" > /dev/null; then
    echo "Closing LibreOffice..."
    # Ctrl+Q usually quits
    safe_xdotool ga :1 key ctrl+q || true
    sleep 1
    # Handle "Save changes?" - Press 'Don't Save' (Alt+D) just in case they didn't save
    safe_xdotool ga :1 key alt+d || true
fi

echo "=== Export complete ==="