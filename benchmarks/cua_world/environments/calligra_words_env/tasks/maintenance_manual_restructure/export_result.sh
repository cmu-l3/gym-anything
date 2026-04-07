#!/bin/bash
set -euo pipefail

echo "=== Exporting Maintenance Manual Restructure Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing the app
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

DOC_PATH="/home/ga/Documents/hvac_maintenance_manual.odt"
DOC_EXISTS="false"
DOC_SIZE="0"
DOC_MTIME="0"

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
fi

# Gently close Calligra to avoid lock file issues, but let the agent's saves persist
DISPLAY=:1 wmctrl -a "Calligra" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+q 2>/dev/null || true
sleep 2
pkill -TERM -f calligrawords 2>/dev/null || true
sleep 1
pkill -KILL -f calligrawords 2>/dev/null || true
rm -f /home/ga/Documents/.~lock.* 2>/dev/null || true

# Export metadata to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc_exists": $DOC_EXISTS,
    "doc_size_bytes": $DOC_SIZE,
    "doc_mtime": $DOC_MTIME,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export Complete ==="