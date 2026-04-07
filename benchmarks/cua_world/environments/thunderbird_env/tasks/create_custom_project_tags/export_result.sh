#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot before closing Thunderbird
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# We must gracefully close Thunderbird to ensure prefs.js and mbox files are flushed to disk
echo "Closing Thunderbird to flush preferences and mbox..."
close_thunderbird
sleep 3

TB_PROFILE="/home/ga/.thunderbird/default-release"
INBOX_FILE="${TB_PROFILE}/Mail/Local Folders/Inbox"
PREFS_FILE="${TB_PROFILE}/prefs.js"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get modification times
PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
INBOX_MTIME=$(stat -c %Y "$INBOX_FILE" 2>/dev/null || echo "0")

# Check if files were modified during the task
PREFS_MODIFIED="false"
INBOX_MODIFIED="false"

if [ "$PREFS_MTIME" -ge "$TASK_START" ]; then
    PREFS_MODIFIED="true"
fi
if [ "$INBOX_MTIME" -ge "$TASK_START" ]; then
    INBOX_MODIFIED="true"
fi

# Prepare output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_modified_during_task": $PREFS_MODIFIED,
    "inbox_modified_during_task": $INBOX_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="