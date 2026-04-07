#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting FCOM Bulletin Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOC_PATH="/home/ga/Documents/b737_winter_ops_bulletin.odt"

# Take final screenshot showing agent's work
take_screenshot /tmp/calligra_fcom_bulletin_final.png

# Record file stats and modification status for anti-gaming
FILE_MODIFIED_DURING_TASK="false"
if [ -f "$DOC_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Do not force-save. The agent must persist its own changes.
# Give it a safe quit command so Calligra writes temporary lock files out.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 3

kill_calligra_processes

# Create a metadata export for the verifier
cat > /tmp/task_result.json << EOF
{
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/calligra_fcom_bulletin_final.png"
}
EOF

echo "=== Export Complete ==="