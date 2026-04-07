#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_FILE="${LOCAL_MAIL_DIR}/Inbox"
PROJECT_DIR="${LOCAL_MAIL_DIR}/ProjectAlpha"
RULES_FILE="${PROFILE_DIR}/msgFilterRules.dat"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Rules file
RULES_EXISTS="false"
RULES_MTIME="0"
RULES_CONTENT=""
if [ -f "$RULES_FILE" ]; then
    RULES_EXISTS="true"
    RULES_MTIME=$(stat -c %Y "$RULES_FILE" 2>/dev/null || echo "0")
    # Base64 encode the content to safely embed in JSON
    RULES_CONTENT=$(base64 -w 0 "$RULES_FILE")
fi

# 2. Check ProjectAlpha folder
FOLDER_EXISTS="false"
FOLDER_MTIME="0"
FOLDER_COUNT="0"
PROJECT_ALPHA_EMAILS="0"

if [ -f "$PROJECT_DIR" ]; then
    FOLDER_EXISTS="true"
    FOLDER_MTIME=$(stat -c %Y "$PROJECT_DIR" 2>/dev/null || echo "0")
    FOLDER_COUNT=$(count_emails_in_mbox "$PROJECT_DIR")
    # Count how many emails have Project Alpha in subject
    PROJECT_ALPHA_EMAILS=$(grep -i "^Subject:.*Project Alpha" "$PROJECT_DIR" | wc -l || echo "0")
fi

# 3. Check Inbox count
CURRENT_INBOX_COUNT=$(count_emails_in_mbox "$INBOX_FILE")

# 4. Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rules_exists": $RULES_EXISTS,
    "rules_mtime": $RULES_MTIME,
    "rules_content_b64": "$RULES_CONTENT",
    "folder_exists": $FOLDER_EXISTS,
    "folder_mtime": $FOLDER_MTIME,
    "folder_count": $FOLDER_COUNT,
    "project_alpha_emails": $PROJECT_ALPHA_EMAILS,
    "current_inbox_count": $CURRENT_INBOX_COUNT,
    "initial_inbox_count": $(cat /tmp/initial_inbox_count.txt 2>/dev/null || echo "0"),
    "app_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="