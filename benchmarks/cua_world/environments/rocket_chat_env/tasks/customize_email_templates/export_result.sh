#!/bin/bash
set -euo pipefail

echo "=== Exporting customize_email_templates result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual records
take_screenshot /tmp/task_final.png

# Re-authenticate to query the final state of the setting
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

SETTING_VALUE=""
SETTING_UPDATED=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Fetch the modified value of Accounts_Enrollment_Email
  SETTING_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_Enrollment_Email" 2>/dev/null || true)
  
  # Extract value and timestamp
  SETTING_VALUE=$(echo "$SETTING_RESP" | jq -r '.value // empty')
  SETTING_UPDATED=$(echo "$SETTING_RESP" | jq -r '._updatedAt // empty')
fi

# Load the initial value recorded during setup
INITIAL_VALUE=""
if [ -f /tmp/initial_setting_value.txt ]; then
  INITIAL_VALUE=$(cat /tmp/initial_setting_value.txt)
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create a JSON result file containing both before and after states
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "setting_value": $(echo "$SETTING_VALUE" | jq -R -s '.'),
  "initial_value": $(echo "$INITIAL_VALUE" | jq -R -s '.'),
  "updated_at": "$SETTING_UPDATED",
  "task_start_time": $TASK_START,
  "task_end_time": $TASK_END
}
EOF

# Move JSON to accessible path
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="