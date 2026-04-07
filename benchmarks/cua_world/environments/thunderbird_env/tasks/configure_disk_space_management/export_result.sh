#!/bin/bash
set -euo pipefail

echo "=== Exporting Configure Disk Space Management Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PROFILE_DIR="/home/ga/.thunderbird/default-release"
PREFS_FILE="${PROFILE_DIR}/prefs.js"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
TRASH_FILE="${LOCAL_MAIL_DIR}/Trash"

# Helper function to extract preference values
get_pref_value() {
    local pref_key="$1"
    if [ -f "$PREFS_FILE" ]; then
        # Matches user_pref("key", value); and extracts value
        grep "\"$pref_key\"" "$PREFS_FILE" 2>/dev/null | sed -E 's/.*,\s*(.*)\);/\1/' | tr -d '"' || echo ""
    else
        echo ""
    fi
}

# 1. Check Global Search and Indexer
INDEXER_ENABLED=$(get_pref_value "mailnews.database.global.indexer.enabled")

# 2. Check Compact Folders Threshold
PURGE_THRESHOLD=$(get_pref_value "mail.purge_threshhold_mb")

# 3. Check Empty Trash on Exit
EMPTY_TRASH=$(get_pref_value "mail.server.server1.empty_trash_on_exit")

# 4. Check Retention Policy Type (retainBy = 2 means 'Delete messages more than X days old')
RETAIN_BY=$(get_pref_value "mail.server.server1.retainBy")

# 5. Check Retention Days
DAYS_TO_KEEP=$(get_pref_value "mail.server.server1.daysToKeepHdrs")

# 6. Check if Trash folder is emptied
TRASH_COUNT=$(count_emails_in_mbox "$TRASH_FILE")
INITIAL_TRASH=$(cat /tmp/initial_trash_count.txt 2>/dev/null || echo "0")

# Check if Thunderbird was running
APP_RUNNING="false"
if is_thunderbird_running; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "indexer_enabled": "$INDEXER_ENABLED",
    "purge_threshold_mb": "$PURGE_THRESHOLD",
    "empty_trash_on_exit": "$EMPTY_TRASH",
    "retain_by": "$RETAIN_BY",
    "days_to_keep": "$DAYS_TO_KEEP",
    "trash_count": $TRASH_COUNT,
    "initial_trash_count": $INITIAL_TRASH,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON exported:"
cat /tmp/task_result.json

echo "=== Export Complete ==="