#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_custom_user_fields result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png

# Login to get the updated setting
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty' 2>/dev/null || echo "")
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty' 2>/dev/null || echo "")

CUSTOM_FIELDS_VALUE=""
UPDATED_AT=""

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  SETTING_RESP=$(curl -sS \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_CustomFields" 2>/dev/null || true)
  
  CUSTOM_FIELDS_VALUE=$(echo "$SETTING_RESP" | jq -r '.value // empty' 2>/dev/null || echo "")
  UPDATED_AT=$(echo "$SETTING_RESP" | jq -r '._updatedAt // empty' 2>/dev/null || echo "")
fi

# Use python to write JSON safely (prevents escaping issues with jq or bash strings)
cat << 'EOF' > /tmp/export_helper.py
import json
import sys

data = {
    'task_start': int(sys.argv[1]),
    'task_end': int(sys.argv[2]),
    'custom_fields_value': sys.argv[3],
    'updated_at': sys.argv[4],
    'screenshot_path': '/tmp/task_final.png'
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
EOF

python3 /tmp/export_helper.py "$TASK_START" "$TASK_END" "$CUSTOM_FIELDS_VALUE" "$UPDATED_AT"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="