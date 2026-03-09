#!/bin/bash
echo "=== Exporting configure_spam_filtering results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GREENFIELD_HOME=$(grep "^greenfield:" /etc/passwd 2>/dev/null | cut -d: -f6)
[ -z "$GREENFIELD_HOME" ] && GREENFIELD_HOME="/home/greenfield"

# ---------------------------------------------------------------
# Collect Configuration Data
# ---------------------------------------------------------------

# 1. Domain Status (to check if spam is enabled)
DOMAIN_INFO=$(virtualmin list-domains --domain greenfield.test --multiline 2>/dev/null || echo "ERROR")
# Escape for JSON
DOMAIN_INFO_JSON=$(json_escape "$DOMAIN_INFO")

# 2. Virtualmin Spam Settings
SPAM_INFO=$(virtualmin list-spam --domain greenfield.test 2>/dev/null || echo "ERROR")
SPAM_INFO_JSON=$(json_escape "$SPAM_INFO")

# 3. SpamAssassin User Prefs
USER_PREFS_PATH="${GREENFIELD_HOME}/.spamassassin/user_prefs"
if [ -f "$USER_PREFS_PATH" ]; then
    USER_PREFS_CONTENT=$(cat "$USER_PREFS_PATH")
    USER_PREFS_MTIME=$(stat -c %Y "$USER_PREFS_PATH")
    USER_PREFS_EXISTS="true"
else
    USER_PREFS_CONTENT=""
    USER_PREFS_MTIME="0"
    USER_PREFS_EXISTS="false"
fi
USER_PREFS_JSON=$(json_escape "$USER_PREFS_CONTENT")

# 4. Procmail Config (for delivery checking)
PROCMAIL_PATH="${GREENFIELD_HOME}/.procmailrc"
if [ -f "$PROCMAIL_PATH" ]; then
    PROCMAIL_CONTENT=$(cat "$PROCMAIL_PATH")
    PROCMAIL_MTIME=$(stat -c %Y "$PROCMAIL_PATH")
else
    PROCMAIL_CONTENT=""
    PROCMAIL_MTIME="0"
fi
PROCMAIL_JSON=$(json_escape "$PROCMAIL_CONTENT")

# 5. Internal Domain Config (Webmin)
# This usually contains the 'spam_delivery' and 'spam_level' raw settings
DOMAIN_ID=$(get_domain_id "greenfield.test")
WEBMIN_DOMAIN_CONF="/etc/webmin/virtual-server/domains/$DOMAIN_ID"
if [ -f "$WEBMIN_DOMAIN_CONF" ]; then
    DOMAIN_CONF_CONTENT=$(cat "$WEBMIN_DOMAIN_CONF")
else
    DOMAIN_CONF_CONTENT=""
fi
DOMAIN_CONF_JSON=$(json_escape "$DOMAIN_CONF_CONTENT")

# ---------------------------------------------------------------
# Anti-Gaming Checks
# ---------------------------------------------------------------
# Check if config changed
INITIAL_PROCMAIL_HASH=$(cat /tmp/initial_procmail_hash.txt 2>/dev/null || echo "none")
CURRENT_PROCMAIL_HASH=$(md5sum "$PROCMAIL_PATH" 2>/dev/null || echo "none")

CONFIG_CHANGED="false"
if [ "$USER_PREFS_MTIME" -gt "$TASK_START" ] || \
   [ "$PROCMAIL_MTIME" -gt "$TASK_START" ] || \
   [ "$INITIAL_PROCMAIL_HASH" != "$CURRENT_PROCMAIL_HASH" ]; then
    CONFIG_CHANGED="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Create Result JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_changed_during_task": $CONFIG_CHANGED,
    "domain_info": "$DOMAIN_INFO_JSON",
    "spam_info": "$SPAM_INFO_JSON",
    "user_prefs_exists": $USER_PREFS_EXISTS,
    "user_prefs_content": "$USER_PREFS_JSON",
    "procmail_content": "$PROCMAIL_JSON",
    "domain_conf_content": "$DOMAIN_CONF_JSON",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"