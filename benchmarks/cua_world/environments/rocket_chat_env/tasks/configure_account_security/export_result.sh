#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_account_security task result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

# Fetch the final settings from the Rocket.Chat API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

TEMP_JSON=$(mktemp)
echo "{}" > "$TEMP_JSON"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  get_setting() {
    local val
    val=$(curl -sS -X GET \
      -H "X-Auth-Token: $AUTH_TOKEN" \
      -H "X-User-Id: $USER_ID" \
      "${ROCKETCHAT_BASE_URL}/api/v1/settings/$1" 2>/dev/null | jq -c '.value // null')
      
    # Use jq to inject the value into our results JSON
    jq --arg key "$1" --argjson val "${val:-null}" '.[$key] = $val' "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"
  }

  echo "Gathering Account settings..."
  get_setting "Accounts_LoginExpiration"
  get_setting "Accounts_Password_Policy_Enabled"
  get_setting "Accounts_Password_Policy_MinLength"
  get_setting "Accounts_Password_Policy_AtLeastOneLowercase"
  get_setting "Accounts_Password_Policy_AtLeastOneUppercase"
  get_setting "Accounts_Password_Policy_AtLeastOneNumber"
  get_setting "Accounts_Password_Policy_AtLeastOneSymbol"
  get_setting "Accounts_Password_Policy_ForbidRepeatingCharacters"
  get_setting "Accounts_Password_Policy_MaxRepeatingCharacters"
  get_setting "Accounts_Password_History_Enabled"
  get_setting "Accounts_Password_History_Amount"
else
  echo "WARNING: Failed to authenticate to API during export."
fi

# Add task metadata
jq --arg start "$TASK_START" --arg end "$TASK_END" '. + {task_start: ($start|tonumber), task_end: ($end|tonumber)}' "$TEMP_JSON" > "${TEMP_JSON}.tmp" && mv "${TEMP_JSON}.tmp" "$TEMP_JSON"

# Move temp file to final destination safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="