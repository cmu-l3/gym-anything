#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Water Quality CCR Compilation Result ==="

# Capture final UI state
take_screenshot /tmp/task_final.png

# Collect file stats for the expected output
OUTPUT_FILE="/home/ga/Desktop/millbrook_ccr_2025.odt"
OUTPUT_EXISTS="false"
OUTPUT_MTIME=0
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Write to temp json then move to ensure permissions are safe
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_mtime": $OUTPUT_MTIME,
    "output_size_bytes": $OUTPUT_SIZE,
    "task_start_time": $TASK_START
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Gracefully shutdown Calligra
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
fi

kill_calligra_processes

echo "=== Export Complete ==="
