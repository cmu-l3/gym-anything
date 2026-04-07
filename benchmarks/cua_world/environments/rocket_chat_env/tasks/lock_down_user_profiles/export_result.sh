#!/bin/bash
set -euo pipefail

echo "=== Exporting lock_down_user_profiles result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Perform setup via API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

TEMP_JSON=$(mktemp)

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  
  # Fetch each setting
  get_setting() {
    val=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/settings/$1" | jq -r '.value // empty' 2>/dev/null || true)
    
    if [ "$val" = "false" ]; then
      echo "false"
    else
      echo "true"
    fi
  }

  real_name=$(get_setting "Accounts_AllowRealNameChange")
  username=$(get_setting "Accounts_AllowUsernameChange")
  email=$(get_setting "Accounts_AllowEmailChange")
  avatar=$(get_setting "Accounts_AllowUserAvatarChange")
  del_account=$(get_setting "Accounts_AllowDeleteOwnAccount")

  cat > "$TEMP_JSON" << EOF
{
  "api_reachable": true,
  "Accounts_AllowRealNameChange": $real_name,
  "Accounts_AllowUsernameChange": $username,
  "Accounts_AllowEmailChange": $email,
  "Accounts_AllowUserAvatarChange": $avatar,
  "Accounts_AllowDeleteOwnAccount": $del_account
}
EOF
else
  cat > "$TEMP_JSON" << EOF
{
  "api_reachable": false
}
EOF
fi

cp "$TEMP_JSON" /tmp/lock_down_user_profiles_result.json
chmod 666 /tmp/lock_down_user_profiles_result.json
rm -f "$TEMP_JSON"

echo "Result JSON exported to /tmp/lock_down_user_profiles_result.json"
cat /tmp/lock_down_user_profiles_result.json
echo "=== Export complete ==="