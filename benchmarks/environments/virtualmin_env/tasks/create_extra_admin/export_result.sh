#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_extra_admin results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# -----------------------------------------------------------------------------
# 1. Check if the admin exists in Virtualmin
# -----------------------------------------------------------------------------
ADMIN_EXISTS="false"
ADMIN_DETAILS=""
RAW_LIST=$(virtualmin list-admins --domain acmecorp.test --name devops_carter --multiline 2>/dev/null || true)

if echo "$RAW_LIST" | grep -q "Username: devops_carter"; then
    ADMIN_EXISTS="true"
    ADMIN_DETAILS="$RAW_LIST"
fi

# Extract description if possible
ACTUAL_DESCRIPTION=$(echo "$RAW_LIST" | grep "Real name:" | sed 's/Real name: //g' | xargs || echo "")

# -----------------------------------------------------------------------------
# 2. Verify Password via Authentication Attempt
# -----------------------------------------------------------------------------
# We attempt to curl localhost:10000 using the new credentials.
# Returns 200 (OK) or 302 (Redirect) if login successful. 401 if failed.
AUTH_SUCCESS="false"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --insecure --user "devops_carter:Carter2024Secure!" https://localhost:10000/ 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    AUTH_SUCCESS="true"
fi

# -----------------------------------------------------------------------------
# 3. Anti-Gaming: Check if file existed before (using the list we saved)
# -----------------------------------------------------------------------------
PRE_EXISTED="false"
if grep -q "devops_carter" /tmp/initial_admins_list.txt 2>/dev/null; then
    PRE_EXISTED="true"
fi

# -----------------------------------------------------------------------------
# 4. Fallback: Check /etc/webmin/miniserv.users directly
# -----------------------------------------------------------------------------
MINISERV_ENTRY_EXISTS="false"
if grep -q "^devops_carter:" /etc/webmin/miniserv.users; then
    MINISERV_ENTRY_EXISTS="true"
fi

# -----------------------------------------------------------------------------
# 5. Take Final Screenshot
# -----------------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------------
# 6. Export JSON
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "admin_exists": $ADMIN_EXISTS,
    "actual_description": "$(json_escape "$ACTUAL_DESCRIPTION")",
    "auth_success": $AUTH_SUCCESS,
    "http_auth_code": "$HTTP_CODE",
    "pre_existed": $PRE_EXISTED,
    "miniserv_entry_exists": $MINISERV_ENTRY_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json