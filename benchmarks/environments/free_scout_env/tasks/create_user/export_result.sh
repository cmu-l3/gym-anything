#!/bin/bash
echo "=== Exporting create_user result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

INITIAL_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_user_count)

EXPECTED_FIRST="Rebecca"
EXPECTED_LAST="Fleming"
EXPECTED_EMAIL="rebecca.fleming@helpdesk.local"

# Search by email first
USER_DATA=$(find_user_by_email "$EXPECTED_EMAIL")
USER_FOUND="false"
USER_ID=""
USER_FIRST=""
USER_LAST=""
USER_EMAIL=""
USER_ROLE=""

if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
    USER_ID=$(echo "$USER_DATA" | cut -f1)
    USER_FIRST=$(echo "$USER_DATA" | cut -f2)
    USER_LAST=$(echo "$USER_DATA" | cut -f3)
    USER_EMAIL=$(echo "$USER_DATA" | cut -f4)
    USER_ROLE=$(echo "$USER_DATA" | cut -f5)
fi

# If not found by email, try by name
if [ "$USER_FOUND" = "false" ]; then
    USER_DATA=$(find_user_by_name "$EXPECTED_FIRST" "$EXPECTED_LAST")
    if [ -n "$USER_DATA" ]; then
        USER_FOUND="true"
        USER_ID=$(echo "$USER_DATA" | cut -f1)
        USER_FIRST=$(echo "$USER_DATA" | cut -f2)
        USER_LAST=$(echo "$USER_DATA" | cut -f3)
        USER_EMAIL=$(echo "$USER_DATA" | cut -f4)
        USER_ROLE=$(echo "$USER_DATA" | cut -f5)
    fi
fi

# If still not found, try newest user
if [ "$USER_FOUND" = "false" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    USER_DATA=$(fs_query "SELECT id, first_name, last_name, email, role FROM users ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$USER_DATA" ]; then
        USER_FOUND="true"
        USER_ID=$(echo "$USER_DATA" | cut -f1)
        USER_FIRST=$(echo "$USER_DATA" | cut -f2)
        USER_LAST=$(echo "$USER_DATA" | cut -f3)
        USER_EMAIL=$(echo "$USER_DATA" | cut -f4)
        USER_ROLE=$(echo "$USER_DATA" | cut -f5)
    fi
fi

# Escape for JSON
USER_FIRST=$(echo "$USER_FIRST" | sed 's/"/\\"/g')
USER_LAST=$(echo "$USER_LAST" | sed 's/"/\\"/g')
USER_EMAIL=$(echo "$USER_EMAIL" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT},
    "current_count": ${CURRENT_COUNT},
    "user_found": ${USER_FOUND},
    "user_id": "${USER_ID}",
    "user_first_name": "${USER_FIRST}",
    "user_last_name": "${USER_LAST}",
    "user_email": "${USER_EMAIL}",
    "user_role": "${USER_ROLE}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
