#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Archival Finding Aid Formatting Result ==="

# Record final state timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

take_screenshot /tmp/calligra_archival_finding_aid_post_task.png

DOC_PATH="/home/ga/Documents/sba_finding_aid.odt"
MODIFIED_DURING_TASK="false"
if [ -f "$DOC_PATH" ]; then
    MTIME=$(stat -c %Y "$DOC_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "$DOC_PATH" || true
else
    echo "Warning: $DOC_PATH is missing"
fi

# The agent must persist its own changes. We trigger clean quit without saving.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2
kill_calligra_processes

# Create export JSON for programmatic verifier
cat > /tmp/task_export.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "modified_during_task": $MODIFIED_DURING_TASK
}
EOF
chmod 666 /tmp/task_export.json 2>/dev/null || true

echo "=== Export Complete ==="