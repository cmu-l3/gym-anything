#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_gdpr_settings result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || true)

# Initialize default values
GDPR_ENABLED="false"
GDPR_ENABLED_TS=""
GDPR_EMAIL=""
GDPR_EMAIL_TS=""
GDPR_DOWNLOAD="false"
GDPR_DOWNLOAD_TS=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch GDPR_Enabled
  RESP_1=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/GDPR_Enabled" 2>/dev/null || true)
  if [ -n "$RESP_1" ]; then
    GDPR_ENABLED=$(echo "$RESP_1" | jq -r '.value // false')
    GDPR_ENABLED_TS=$(echo "$RESP_1" | jq -r '._updatedAt // empty')
  fi

  # Fetch GDPR_Contact_Email
  RESP_2=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/GDPR_Contact_Email" 2>/dev/null || true)
  if [ -n "$RESP_2" ]; then
    GDPR_EMAIL=$(echo "$RESP_2" | jq -r '.value // empty')
    GDPR_EMAIL_TS=$(echo "$RESP_2" | jq -r '._updatedAt // empty')
  fi

  # Fetch GDPR_Allow_Data_Download
  RESP_3=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/GDPR_Allow_Data_Download" 2>/dev/null || true)
  if [ -n "$RESP_3" ]; then
    GDPR_DOWNLOAD=$(echo "$RESP_3" | jq -r '.value // false')
    GDPR_DOWNLOAD_TS=$(echo "$RESP_3" | jq -r '._updatedAt // empty')
  fi
fi

# Ensure boolean strings for jq
if [ "$GDPR_ENABLED" != "true" ]; then GDPR_ENABLED="false"; fi
if [ "$GDPR_DOWNLOAD" != "true" ]; then GDPR_DOWNLOAD="false"; fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
  --arg start_ts "$TASK_START" \
  --arg end_ts "$TASK_END" \
  --argjson gdpr_enabled "$GDPR_ENABLED" \
  --arg gdpr_email "$GDPR_EMAIL" \
  --argjson gdpr_download "$GDPR_DOWNLOAD" \
  --arg gdpr_enabled_ts "$GDPR_ENABLED_TS" \
  --arg gdpr_email_ts "$GDPR_EMAIL_TS" \
  --arg gdpr_download_ts "$GDPR_DOWNLOAD_TS" \
  '{
    task_start: $start_ts|tonumber,
    task_end: $end_ts|tonumber,
    gdpr_enabled: $gdpr_enabled,
    gdpr_email: $gdpr_email,
    gdpr_download: $gdpr_download,
    gdpr_enabled_ts: $gdpr_enabled_ts,
    gdpr_email_ts: $gdpr_email_ts,
    gdpr_download_ts: $gdpr_download_ts
  }' > "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="