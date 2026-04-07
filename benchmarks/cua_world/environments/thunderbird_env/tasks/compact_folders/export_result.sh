#!/bin/bash
set -e
echo "=== Exporting compact_folders result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Paths
PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
JUNK_MBOX="${LOCAL_MAIL_DIR}/Junk"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Gather current file stats
INBOX_FINAL_SIZE=$(stat -c%s "$INBOX_MBOX" 2>/dev/null || echo "0")
JUNK_FINAL_SIZE=$(stat -c%s "$JUNK_MBOX" 2>/dev/null || echo "0")

INBOX_FINAL_COUNT=$(grep -c "^From " "$INBOX_MBOX" 2>/dev/null || echo "0")
JUNK_FINAL_COUNT=$(grep -c "^From " "$JUNK_MBOX" 2>/dev/null || echo "0")

INBOX_MTIME=$(stat -c%Y "$INBOX_MBOX" 2>/dev/null || echo "0")
JUNK_MTIME=$(stat -c%Y "$JUNK_MBOX" 2>/dev/null || echo "0")

INBOX_MODIFIED="false"
JUNK_MODIFIED="false"
if [ "$INBOX_MTIME" -gt "$TASK_START" ]; then INBOX_MODIFIED="true"; fi
if [ "$JUNK_MTIME" -gt "$TASK_START" ]; then JUNK_MODIFIED="true"; fi

# 3. Retrieve initial states established in setup
INBOX_INITIAL_SIZE=$(python3 -c "import json; print(json.load(open('/tmp/initial_sizes.json')).get('inbox_initial_size', 0))" 2>/dev/null || echo "0")
JUNK_INITIAL_SIZE=$(python3 -c "import json; print(json.load(open('/tmp/initial_sizes.json')).get('junk_initial_size', 0))" 2>/dev/null || echo "0")
INBOX_ACTIVE=$(python3 -c "import json; print(json.load(open('/tmp/initial_sizes.json')).get('inbox_active_count', 0))" 2>/dev/null || echo "0")
JUNK_ACTIVE=$(python3 -c "import json; print(json.load(open('/tmp/initial_sizes.json')).get('junk_active_count', 0))" 2>/dev/null || echo "0")

# 4. Construct final result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "inbox_initial_size": $INBOX_INITIAL_SIZE,
    "junk_initial_size": $JUNK_INITIAL_SIZE,
    "inbox_initial_active": $INBOX_ACTIVE,
    "junk_initial_active": $JUNK_ACTIVE,
    "inbox_final_size": $INBOX_FINAL_SIZE,
    "junk_final_size": $JUNK_FINAL_SIZE,
    "inbox_final_active": $INBOX_FINAL_COUNT,
    "junk_final_active": $JUNK_FINAL_COUNT,
    "inbox_modified_during_task": $INBOX_MODIFIED,
    "junk_modified_during_task": $JUNK_MODIFIED,
    "task_start_time": $TASK_START
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="