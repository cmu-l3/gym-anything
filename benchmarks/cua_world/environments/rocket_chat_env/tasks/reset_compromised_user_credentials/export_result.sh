#!/bin/bash
set -euo pipefail

echo "=== Exporting reset_compromised_user_credentials task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Attempt to log in as dev.lead with the new expected password
LOGIN_PAYLOAD='{"user":"dev.lead","password":"Recovery#2026!"}'
LOGIN_RESP=$(curl -sS -X POST -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD" "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

# The API returns 200 OK with success: true and data.authToken if login is successful.
# If 2FA is required, it returns 401 Unauthorized with error: "totp-required".
# If wrong password, it returns 401 Unauthorized with error: "error-login-blocked" or "Unauthorized".

LOGIN_STATUS=$(echo "$LOGIN_RESP" | jq -r '.status // .success // "false"')
if [ "$LOGIN_STATUS" = "success" ] || [ "$LOGIN_STATUS" = "true" ]; then
  LOGIN_SUCCESS="true"
else
  LOGIN_SUCCESS="false"
fi
LOGIN_ERROR=$(echo "$LOGIN_RESP" | jq -r '.error // empty')

# Get user info using Admin token to check requirePasswordChange
ADMIN_LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo "{}")

AUTH_TOKEN=$(echo "$ADMIN_LOGIN_RESP" | jq -r '.data.authToken // empty')
ADMIN_ID=$(echo "$ADMIN_LOGIN_RESP" | jq -r '.data.userId // empty')

REQUIRE_PW_CHANGE="false"
USER_EXISTS="false"

if [ -n "$AUTH_TOKEN" ] && [ -n "$ADMIN_ID" ]; then
    USER_INFO=$(curl -sS \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $ADMIN_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/users.info?username=dev.lead" 2>/dev/null || echo "{}")

    USER_EXISTS_STATUS=$(echo "$USER_INFO" | jq -r '.success // "false"')
    if [ "$USER_EXISTS_STATUS" = "true" ]; then
        USER_EXISTS="true"
        PW_CHANGE_VAL=$(echo "$USER_INFO" | jq -r '.user.requirePasswordChange // "false"')
        if [ "$PW_CHANGE_VAL" = "true" ]; then
            REQUIRE_PW_CHANGE="true"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "login_success": $LOGIN_SUCCESS,
    "login_error": "${LOGIN_ERROR:-}",
    "user_exists": $USER_EXISTS,
    "require_pw_change": $REQUIRE_PW_CHANGE,
    "task_end_timestamp": $(date +%s)
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="