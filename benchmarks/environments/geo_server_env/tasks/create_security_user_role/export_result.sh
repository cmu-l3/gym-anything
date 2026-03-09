#!/bin/bash
echo "=== Exporting create_security_user_role result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- 1. Check Role Existence ---
ROLE_CHECK=$(curl -s -u "$GS_AUTH" -o /dev/null -w "%{http_code}" "${GS_REST}/security/roles/role/ROLE_DATA_ANALYST")
ROLE_EXISTS="false"
if [ "$ROLE_CHECK" = "200" ]; then
    ROLE_EXISTS="true"
fi

# --- 2. Check User Existence ---
USER_CHECK=$(curl -s -u "$GS_AUTH" -o /dev/null -w "%{http_code}" "${GS_REST}/security/usergroup/user/analyst_jones")
USER_EXISTS="false"
if [ "$USER_CHECK" = "200" ]; then
    USER_EXISTS="true"
fi

# --- 3. Check Role Assignment ---
# We check if the role contains the user
ROLE_ASSIGNMENT_CHECK=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/roles/role/ROLE_DATA_ANALYST/user/analyst_jones")
ROLE_ASSIGNED="false"
# Note: The REST API might return 404 if not assigned, or list users.
# A more robust check is listing users of the role.
ROLE_USERS=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/roles/role/ROLE_DATA_ANALYST/users.json" 2>/dev/null)
if echo "$ROLE_USERS" | grep -q "analyst_jones"; then
    ROLE_ASSIGNED="true"
fi

# --- 4. Verify Authentication (The ultimate test) ---
# Try to access a protected resource using the new user's credentials
AUTH_TEST_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "analyst_jones:Analyst2024!" "${GS_REST}/about/version.json")
AUTH_SUCCESS="false"
if [ "$AUTH_TEST_CODE" = "200" ]; then
    AUTH_SUCCESS="true"
fi

# --- 5. Check Agent's Output File ---
FILE_PATH="/home/ga/auth_test_result.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$FILE_PATH" | tr -d '[:space:]')
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# --- 6. Check Counts for Anti-Gaming ---
INITIAL_ROLES=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")
INITIAL_USERS=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
CURRENT_ROLES=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/roles.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('roles', [])))" 2>/dev/null || echo "0")
CURRENT_USERS=$(curl -s -u "$GS_AUTH" "${GS_REST}/security/usergroup/users.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('users', [])))" 2>/dev/null || echo "0")

# --- 7. GUI Interaction ---
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "role_exists": $ROLE_EXISTS,
    "user_exists": $USER_EXISTS,
    "role_assigned": $ROLE_ASSIGNED,
    "auth_success": $AUTH_SUCCESS,
    "auth_http_code": "$AUTH_TEST_CODE",
    "file_exists": $FILE_EXISTS,
    "file_content": "$(json_escape "$FILE_CONTENT")",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "initial_roles": $INITIAL_ROLES,
    "current_roles": $CURRENT_ROLES,
    "initial_users": $INITIAL_USERS,
    "current_users": $CURRENT_USERS,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_security_user_role_result.json"

echo "=== Export complete ==="