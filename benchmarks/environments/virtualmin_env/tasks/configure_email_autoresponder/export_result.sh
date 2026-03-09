#!/bin/bash
echo "=== Exporting configure_email_autoresponder result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get sarah's home directory
SARAH_HOME=$(cat /tmp/sarah_home_path.txt 2>/dev/null || echo "")
if [ -z "$SARAH_HOME" ]; then
    SARAH_HOME=$(virtualmin list-users --domain acmecorp.test --user-name sarah --multiline 2>/dev/null | grep "Home directory" | awk '{print $NF}')
fi
if [ -z "$SARAH_HOME" ]; then
    SARAH_HOME="/home/acmecorp/homes/sarah"
fi

# ---------------------------------------------------------------
# Check 1: Virtualmin CLI Status
# ---------------------------------------------------------------
USER_INFO=$(virtualmin list-users --domain acmecorp.test --user-name sarah --multiline 2>/dev/null || true)
AUTORESPONDER_ENABLED="false"

if echo "$USER_INFO" | grep -qi "autoresponder.*yes\|auto.reply.*enabled\|Autoresponder: Yes"; then
    AUTORESPONDER_ENABLED="true"
fi

# ---------------------------------------------------------------
# Check 2: Physical File Detection
# ---------------------------------------------------------------
AUTOREPLY_FILE=""
AUTOREPLY_CONTENT=""
FILE_TIME="0"

# Look for common autoreply files
for f in "${SARAH_HOME}/autoreply.txt" "${SARAH_HOME}/.autoreply.txt" "${SARAH_HOME}/autoreply.msg" "${SARAH_HOME}/.autoreply-message.txt"; do
    if [ -f "$f" ]; then
        AUTOREPLY_FILE="$f"
        FILE_TIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        AUTOREPLY_CONTENT=$(cat "$f" 2>/dev/null || true)
        break
    fi
done

# Fallback: extract message from CLI if file not found but enabled
if [ -z "$AUTOREPLY_CONTENT" ] && [ "$AUTORESPONDER_ENABLED" = "true" ]; then
    AUTOREPLY_CONTENT=$(virtualmin list-users --domain acmecorp.test --user-name sarah --multiline 2>/dev/null | sed -n '/Autoresponder message/,/^[^ ]/p' | tail -n +2 || true)
fi

# ---------------------------------------------------------------
# Check 3: Configuration Persistence
# ---------------------------------------------------------------
FILE_CREATED_DURING_TASK="false"
if [ "$FILE_TIME" -ge "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Export to JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "autoresponder_enabled": $AUTORESPONDER_ENABLED,
    "autoreply_file_path": "$AUTOREPLY_FILE",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "autoreply_content_length": ${#AUTOREPLY_CONTENT},
    "autoreply_content": "$(json_escape "$AUTOREPLY_CONTENT")",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="