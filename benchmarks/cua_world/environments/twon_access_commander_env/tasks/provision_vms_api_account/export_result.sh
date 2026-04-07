#!/bin/bash
echo "=== Exporting provision_vms_api_account result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Re-authenticate as admin to fetch data
ac_login

# 1. Fetch the user "Milestone VMS_Service"
USER_EXISTS="false"
USER_EMAIL=""
USER_CARDS="[]"
USER_PIN_CONFIGURED="false"
USER_CREATED_DURING_TASK="false"

USER_DATA=$(ac_api GET "/users" | jq -c '.[] | select(.firstName=="Milestone" and .lastName=="VMS_Service")' 2>/dev/null)

if [ -n "$USER_DATA" ] && [ "$USER_DATA" != "null" ]; then
    USER_EXISTS="true"
    USER_EMAIL=$(echo "$USER_DATA" | jq -r '.email // empty')
    USER_ID=$(echo "$USER_DATA" | jq -r '.id')
    
    # Fetch detailed user profile to check for physical credentials
    USER_DETAIL=$(ac_api GET "/users/$USER_ID" 2>/dev/null)
    USER_CARDS=$(echo "$USER_DETAIL" | jq -c '.cards // []')
    
    # PIN could be a string or a boolean depending on API version, check if it's set
    HAS_PIN=$(echo "$USER_DETAIL" | jq -r 'if (.pin != null and .pin != "") or (.pinCode != null and .pinCode != "") then "true" else "false" end')
    if [ "$HAS_PIN" = "true" ]; then
        USER_PIN_CONFIGURED="true"
    fi

    # Check if created during task
    USER_CREATED_DURING_TASK="true"
fi

# 2. Test API authentication with the provisioned credentials
rm -f /tmp/test_api_cookies.txt
API_LOGIN_HTTP=$(curl -sk -c /tmp/test_api_cookies.txt \
    -o /tmp/api_login_resp.json \
    -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d '{"login":"api_milestone","password":"ApiAuth#2026_xP!"}' \
    "${AC_URL}/api/v3/auth")

API_LOGIN_SUCCESS="false"
ADMIN_ACCESS_SUCCESS="false"

if [ "$API_LOGIN_HTTP" = "200" ] || [ "$API_LOGIN_HTTP" = "201" ]; then
    API_LOGIN_SUCCESS="true"
    
    # 3. Test administrative privileges
    # The /api/v3/system/info endpoint requires system administration rights
    # Standard users or device managers will get 403 Forbidden
    ADMIN_TEST_HTTP=$(curl -sk -b /tmp/test_api_cookies.txt \
        -o /dev/null \
        -w "%{http_code}" \
        "${AC_URL}/api/v3/system/info")
        
    if [ "$ADMIN_TEST_HTTP" = "200" ]; then
        ADMIN_ACCESS_SUCCESS="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_exists": $USER_EXISTS,
    "user_created_during_task": $USER_CREATED_DURING_TASK,
    "user_email": "$USER_EMAIL",
    "api_login_success": $API_LOGIN_SUCCESS,
    "admin_access_success": $ADMIN_ACCESS_SUCCESS,
    "user_cards": $USER_CARDS,
    "user_pin_configured": $USER_PIN_CONFIGURED
}
EOF

# Ensure safe file permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="