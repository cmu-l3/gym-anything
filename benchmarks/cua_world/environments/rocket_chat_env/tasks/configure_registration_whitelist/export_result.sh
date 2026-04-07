#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_registration_whitelist task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Authenticate via API to fetch the configured settings
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch current setting values
  VAL_REG=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_RegistrationForm" | jq -r '.value // empty')
  VAL_DOM=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_AllowedDomainsList" | jq -r '.value // empty')
  VAL_PROF=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_AllowUserProfileChange" | jq '.value')
  VAL_NAME=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_AllowRealNameChange" | jq '.value')
  
  # Format result into JSON carefully
  TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
  jq -n \
    --arg reg "$VAL_REG" \
    --arg dom "$VAL_DOM" \
    --argjson prof "${VAL_PROF:-null}" \
    --argjson name "${VAL_NAME:-null}" \
    '{
      "Accounts_RegistrationForm": $reg,
      "Accounts_AllowedDomainsList": $dom,
      "Accounts_AllowUserProfileChange": $prof,
      "Accounts_AllowRealNameChange": $name
    }' > "$TEMP_JSON"
    
  # Deploy result to final accessible location
  rm -f /tmp/task_result.json 2>/dev/null || true
  cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || true
  chmod 666 /tmp/task_result.json 2>/dev/null || true
  rm -f "$TEMP_JSON"
else
  echo "ERROR: Could not authenticate to export results."
  echo "{}" > /tmp/task_result.json
  chmod 666 /tmp/task_result.json 2>/dev/null || true
fi

echo "Export complete. Result:"
cat /tmp/task_result.json