#!/bin/bash
set -e
echo "=== Exporting edit_mailbox_properties result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Get ID of the mailbox we created in setup
MAILBOX_ID=$(cat /tmp/target_mailbox_id.txt 2>/dev/null || echo "")

# 3. Query current state of THAT specific mailbox ID
# This prevents the agent from just creating a NEW mailbox and leaving the old one
MAILBOX_FOUND="false"
CURRENT_NAME=""
CURRENT_EMAIL=""
CURRENT_ALIASES=""

if [ -n "$MAILBOX_ID" ]; then
    # Helper query to get JSON-friendly output
    # Note: Aliases are stored as JSON array or serialized string in DB depending on version,
    # but usually just a text field in FreeScout. We grab the raw value.
    RESULT=$(fs_query "SELECT name, email, aliases FROM mailboxes WHERE id = $MAILBOX_ID LIMIT 1" 2>/dev/null)
    
    if [ -n "$RESULT" ]; then
        MAILBOX_FOUND="true"
        CURRENT_NAME=$(echo "$RESULT" | cut -f1)
        CURRENT_EMAIL=$(echo "$RESULT" | cut -f2)
        CURRENT_ALIASES=$(echo "$RESULT" | cut -f3)
    fi
fi

# 4. Get counts for anti-gaming check
INITIAL_COUNT=$(cat /tmp/initial_mailbox_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_mailbox_count)

# 5. Escape strings for JSON safety
SAFE_NAME=$(echo "$CURRENT_NAME" | sed 's/"/\\"/g')
SAFE_EMAIL=$(echo "$CURRENT_EMAIL" | sed 's/"/\\"/g')
SAFE_ALIASES=$(echo "$CURRENT_ALIASES" | sed 's/"/\\"/g')

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mailbox_found": $MAILBOX_FOUND,
    "mailbox_id": "$MAILBOX_ID",
    "current_name": "$SAFE_NAME",
    "current_email": "$SAFE_EMAIL",
    "current_aliases": "$SAFE_ALIASES",
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 7. Write to final location with proper permissions
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="