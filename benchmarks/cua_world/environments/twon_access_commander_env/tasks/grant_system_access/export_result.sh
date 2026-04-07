#!/bin/bash
echo "=== Exporting grant_system_access result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png ga

# ================================================================
# 1. Test Original Admin Account
# ================================================================
echo "Testing original admin credentials..."
ADMIN_HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d '{"login":"admin","password":"2n"}' "${AC_URL}/api/v3/auth")

if [ "$ADMIN_HTTP" = "200" ] || [ "$ADMIN_HTTP" = "201" ]; then
    ADMIN_INTACT="true"
    echo "  -> Original admin intact"
else
    ADMIN_INTACT="false"
    echo "  -> WARNING: Original admin failed authentication (HTTP $ADMIN_HTTP)"
fi

# ================================================================
# 2. Test New User Login
# ================================================================
echo "Testing new credentials (vschulz / SecurePass2026!)..."
NEW_HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d '{"login":"vschulz","password":"SecurePass2026!"}' "${AC_URL}/api/v3/auth")

if [ "$NEW_HTTP" = "200" ] || [ "$NEW_HTTP" = "201" ]; then
    NEW_LOGIN_SUCCESS="true"
    echo "  -> New login successful"
else
    NEW_LOGIN_SUCCESS="false"
    echo "  -> New login failed (HTTP $NEW_HTTP)"
fi

# ================================================================
# 3. Query Database for User State (Using original admin)
# ================================================================
USER_UNIQUE="false"
VICTOR_LOGIN=""
VICTOR_PRIVS="[]"
VICTOR_COUNT=0

if [ "$ADMIN_INTACT" = "true" ]; then
    ac_login > /dev/null 2>&1
    USERS_JSON=$(ac_api GET "/users" 2>/dev/null)
    
    # Count how many Victor Schulzes exist
    VICTOR_COUNT=$(echo "$USERS_JSON" | jq '[.[] | select(.firstName=="Victor" and .lastName=="Schulz")] | length' 2>/dev/null || echo "0")
    
    if [ "$VICTOR_COUNT" -eq 1 ]; then
        USER_UNIQUE="true"
        VICTOR_LOGIN=$(echo "$USERS_JSON" | jq -r '.[] | select(.firstName=="Victor" and .lastName=="Schulz") | .login // empty' 2>/dev/null)
        VICTOR_PRIVS=$(echo "$USERS_JSON" | jq -c '.[] | select(.firstName=="Victor" and .lastName=="Schulz") | .privileges // []' 2>/dev/null)
    elif [ "$VICTOR_COUNT" -gt 1 ]; then
        echo "  -> WARNING: Multiple 'Victor Schulz' users found."
    else
        echo "  -> WARNING: 'Victor Schulz' not found."
    fi
else
    echo "Cannot query user database: admin account is locked/broken."
fi

# Escape privileges string for JSON
VICTOR_PRIVS_ESC=$(echo "$VICTOR_PRIVS" | sed 's/"/\\"/g')

# ================================================================
# 4. Generate Results JSON
# ================================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "admin_intact": $ADMIN_INTACT,
    "new_login_success": $NEW_LOGIN_SUCCESS,
    "victor_count": $VICTOR_COUNT,
    "user_unique": $USER_UNIQUE,
    "victor_login": "$VICTOR_LOGIN",
    "victor_privileges": "$VICTOR_PRIVS_ESC",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="