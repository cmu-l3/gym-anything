#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
TEMPLATES_FILE="${LOCAL_MAIL_DIR}/Templates"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Ensure Thunderbird syncs files to disk
sync
sleep 2

# Gather file modification times and sizes
TEMPLATES_MTIME=$(stat -c %Y "$TEMPLATES_FILE" 2>/dev/null || echo "0")
TEMPLATES_SIZE=$(stat -c %s "$TEMPLATES_FILE" 2>/dev/null || echo "0")

# Determine if Templates file was modified during the task
MODIFIED_DURING_TASK="false"
if [ "$TEMPLATES_MTIME" -gt "$TASK_START" ] && [ "$TEMPLATES_SIZE" -gt 0 ]; then
    MODIFIED_DURING_TASK="true"
fi

# Copy mbox files to /tmp for safe extraction by verifier
cp "${LOCAL_MAIL_DIR}/Templates" /tmp/tb_templates.mbox 2>/dev/null || touch /tmp/tb_templates.mbox
cp "${LOCAL_MAIL_DIR}/Drafts" /tmp/tb_drafts.mbox 2>/dev/null || touch /tmp/tb_drafts.mbox
cp "${LOCAL_MAIL_DIR}/Sent" /tmp/tb_sent.mbox 2>/dev/null || touch /tmp/tb_sent.mbox
chmod 666 /tmp/tb_*.mbox

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "templates_mtime": $TEMPLATES_MTIME,
    "templates_size": $TEMPLATES_SIZE,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "thunderbird_running": $(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false"),
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# Safely move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="