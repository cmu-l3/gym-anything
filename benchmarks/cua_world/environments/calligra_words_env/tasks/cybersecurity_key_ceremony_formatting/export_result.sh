#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Cybersecurity Key Ceremony Formatting Result ==="

# Bring window to foreground for accurate final screenshot
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

take_screenshot /tmp/calligra_post_task_screenshot.png

# Safely close Calligra Words without force-saving (evaluates user's persistence)
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

# Record export metrics
OUTPUT_PATH="/home/ga/Documents/root_ca_ceremony.odt"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "$OUTPUT_PATH" || true
else
    OUTPUT_MTIME="0"
    OUTPUT_SIZE="0"
    echo "Warning: $OUTPUT_PATH is missing"
fi

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Package basic task stats (Verifier primarily uses the ODT parser via copy_from_env)
cat > /tmp/task_result.json << EOF
{
    "file_modified": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "=== Export Complete ==="