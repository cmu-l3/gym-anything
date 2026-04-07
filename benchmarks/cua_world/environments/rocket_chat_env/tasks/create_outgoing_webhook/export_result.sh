#!/bin/bash
set -euo pipefail

echo "=== Exporting create_outgoing_webhook task results ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_outgoing_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch integrations via API
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","password":"Admin1234!"}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || echo '{}')

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

OUTGOING_JSON="[]"
if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  INTEGRATIONS_RESP=$(curl -sS -X GET \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" 2>/dev/null || echo '{}')
  
  OUTGOING_JSON=$(echo "$INTEGRATIONS_RESP" | jq -c '[.integrations[]? | select(.type == "webhook-outgoing")]' 2>/dev/null || echo "[]")
fi

# Export to JSON result using a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "outgoing_webhooks": $OUTGOING_JSON
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="