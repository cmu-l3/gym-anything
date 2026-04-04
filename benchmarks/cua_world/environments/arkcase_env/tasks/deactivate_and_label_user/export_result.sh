#!/bin/bash
# post_task: Export results for verification
# 1. Check functional login (should fail)
# 2. Check user details via API
# 3. Verify admin session is still active

echo "=== Exporting deactivate_and_label_user results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TARGET_USER="audit-temp@dev.arkcase.com"
TARGET_PASS="AuditTemp123!"

# ------------------------------------------------------------------
# 1. Functional Login Check (Should FAIL if deactivated)
# ------------------------------------------------------------------
echo "Testing login for target user..."
LOGIN_HTTP_CODE=$(curl -k -o /dev/null -w "%{http_code}" -X POST \
    -d "j_username=${TARGET_USER}&j_password=${TARGET_PASS}&submit=Login" \
    "${ARKCASE_URL}/j_spring_security_check" 2>/dev/null)

echo "Login HTTP Code: $LOGIN_HTTP_CODE"

LOGIN_BLOCKED="false"
# ArkCase typically redirects to login?error=true or returns 401/403 on failure
# A successful login usually redirects (302) to home
if [ "$LOGIN_HTTP_CODE" != "302" ] && [ "$LOGIN_HTTP_CODE" != "200" ]; then
    LOGIN_BLOCKED="true"
elif [ "$LOGIN_HTTP_CODE" = "302" ]; then
    # Check where it redirects
    REDIRECT_LOC=$(curl -k -i -X POST -d "j_username=${TARGET_USER}&j_password=${TARGET_PASS}&submit=Login" "${ARKCASE_URL}/j_spring_security_check" 2>/dev/null | grep -i "Location:" | awk '{print $2}')
    if echo "$REDIRECT_LOC" | grep -q "error"; then
        LOGIN_BLOCKED="true"
    else
        LOGIN_BLOCKED="false"
    fi
fi

# ------------------------------------------------------------------
# 2. API State Check (Get User Details)
# ------------------------------------------------------------------
echo "Fetching user details from API..."
# We use the python script to fetch and parse because bash JSON parsing is fragile
# We need to use Admin credentials to fetch the user
USER_JSON=$(arkcase_api GET "users/user/${TARGET_USER}" 2>/dev/null)

# Save raw JSON for debugging
echo "$USER_JSON" > /tmp/user_final_state.json

# Parse values
USER_ACTIVE=$(echo "$USER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('active', 'unknown'))" 2>/dev/null || echo "unknown")
USER_TITLE=$(echo "$USER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('title', ''))" 2>/dev/null || echo "")
USER_EXISTS=$(echo "$USER_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); print('true' if 'email' in d else 'false')" 2>/dev/null || echo "false")

echo "Parsed State -> Active: $USER_ACTIVE, Title: '$USER_TITLE', Exists: $USER_EXISTS"

# ------------------------------------------------------------------
# 3. LDAP State Check (Backup verification)
# ------------------------------------------------------------------
# Check if account is disabled in Samba AD (UserAccountControl flag 514 = disabled, 512 = enabled)
LDAP_STATUS=$(kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool user show audit-temp 2>/dev/null | grep "userAccountControl" | awk '{print $2}')
echo "LDAP UAC: $LDAP_STATUS"

# ------------------------------------------------------------------
# 4. Screenshot Evidence
# ------------------------------------------------------------------
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# ------------------------------------------------------------------
# 5. Compile Result JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "login_blocked": $LOGIN_BLOCKED,
    "login_http_code": "$LOGIN_HTTP_CODE",
    "user_exists_in_api": $USER_EXISTS,
    "api_active_status": $USER_ACTIVE,
    "api_job_title": "$USER_TITLE",
    "ldap_uac": "$LDAP_STATUS",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json