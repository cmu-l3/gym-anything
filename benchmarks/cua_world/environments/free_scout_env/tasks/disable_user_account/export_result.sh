#!/bin/bash
echo "=== Exporting disable_user_account result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get stored initial values
INITIAL_STATUS=$(cat /tmp/initial_target_status.txt 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
INITIAL_ADMIN_STATUS=$(cat /tmp/initial_admin_status.txt 2>/dev/null || echo "1")

# Get current state of Target User
TARGET_EMAIL="marcus.webb@helpdesk.local"
TARGET_DATA=$(fs_query "SELECT id, status FROM users WHERE email = '$TARGET_EMAIL' LIMIT 1" 2>/dev/null)

TARGET_FOUND="false"
TARGET_ID=""
CURRENT_STATUS=""

if [ -n "$TARGET_DATA" ]; then
    TARGET_FOUND="true"
    TARGET_ID=$(echo "$TARGET_DATA" | cut -f1)
    CURRENT_STATUS=$(echo "$TARGET_DATA" | cut -f2)
fi

# Get current state of Admin User
ADMIN_DATA=$(fs_query "SELECT status FROM users WHERE email = 'admin@helpdesk.local' LIMIT 1" 2>/dev/null)
CURRENT_ADMIN_STATUS=$(echo "$ADMIN_DATA" | tr -d '[:space:]')

# Get current user count
CURRENT_USER_COUNT=$(get_user_count)

# Determine if record was deleted
RECORD_DELETED="false"
if [ "$TARGET_FOUND" = "false" ]; then
    RECORD_DELETED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_found": $TARGET_FOUND,
    "record_deleted": $RECORD_DELETED,
    "initial_status": "${INITIAL_STATUS}",
    "current_status": "${CURRENT_STATUS}",
    "initial_user_count": ${INITIAL_USER_COUNT},
    "current_user_count": ${CURRENT_USER_COUNT},
    "initial_admin_status": "${INITIAL_ADMIN_STATUS}",
    "current_admin_status": "${CURRENT_ADMIN_STATUS}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="