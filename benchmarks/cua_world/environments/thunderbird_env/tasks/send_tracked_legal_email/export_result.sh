#!/bin/bash
echo "=== Exporting Send Tracked Legal Email Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot before extracting data
take_screenshot /tmp/task_final.png

# 2. Allow Thunderbird to flush background saves
sleep 3

# 3. Retrieve Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Check for Sent folder existence and copy it
SENT_MBOX="/home/ga/.thunderbird/default-release/Mail/Local Folders/Sent"
SENT_EXISTS="false"
SENT_MODIFIED_DURING_TASK="false"

if [ -f "$SENT_MBOX" ]; then
    SENT_EXISTS="true"
    cp "$SENT_MBOX" /tmp/Sent.mbox
    chmod 666 /tmp/Sent.mbox
    
    SENT_MTIME=$(stat -c %Y "$SENT_MBOX" 2>/dev/null || echo "0")
    if [ "$SENT_MTIME" -gt "$TASK_START" ]; then
        SENT_MODIFIED_DURING_TASK="true"
    fi
fi

# 5. Export metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sent_exists": $SENT_EXISTS,
    "sent_modified_during_task": $SENT_MODIFIED_DURING_TASK
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="