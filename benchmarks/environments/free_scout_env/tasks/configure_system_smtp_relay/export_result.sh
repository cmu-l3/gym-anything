#!/bin/bash
echo "=== Exporting configure_system_smtp_relay result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Fetch current settings from database
MAIL_DRIVER=$(fs_query "SELECT option_value FROM options WHERE option_key='mail_driver'" 2>/dev/null)
MAIL_HOST=$(fs_query "SELECT option_value FROM options WHERE option_key='mail_host'" 2>/dev/null)
MAIL_PORT=$(fs_query "SELECT option_value FROM options WHERE option_key='mail_port'" 2>/dev/null)
MAIL_FROM_ADDR=$(fs_query "SELECT option_value FROM options WHERE option_key='mail_from_address'" 2>/dev/null)
MAIL_FROM_NAME=$(fs_query "SELECT option_value FROM options WHERE option_key='mail_from_name'" 2>/dev/null)
MAIL_ENCRYPTION=$(fs_query "SELECT option_value FROM options WHERE option_key='mail_encryption'" 2>/dev/null)
MAIL_USERNAME=$(fs_query "SELECT option_value FROM options WHERE option_key='mail_username'" 2>/dev/null)

# Check mock SMTP logs for activity
SMTP_ACTIVITY="false"
if [ -f /tmp/smtp_relay.log ]; then
    if grep -q "Connection from" /tmp/smtp_relay.log; then
        SMTP_ACTIVITY="true"
    fi
fi

# Escape for JSON
MAIL_DRIVER=$(echo "$MAIL_DRIVER" | sed 's/"/\\"/g')
MAIL_HOST=$(echo "$MAIL_HOST" | sed 's/"/\\"/g')
MAIL_FROM_NAME=$(echo "$MAIL_FROM_NAME" | sed 's/"/\\"/g')

# Handle NULLs/Empty
[ -z "$MAIL_ENCRYPTION" ] || [ "$MAIL_ENCRYPTION" = "NULL" ] && MAIL_ENCRYPTION=""
[ -z "$MAIL_USERNAME" ] && MAIL_USERNAME=""

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mail_driver": "${MAIL_DRIVER}",
    "mail_host": "${MAIL_HOST}",
    "mail_port": "${MAIL_PORT}",
    "mail_from_address": "${MAIL_FROM_ADDR}",
    "mail_from_name": "${MAIL_FROM_NAME}",
    "mail_encryption": "${MAIL_ENCRYPTION}",
    "mail_username": "${MAIL_USERNAME}",
    "smtp_connection_detected": ${SMTP_ACTIVITY},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="