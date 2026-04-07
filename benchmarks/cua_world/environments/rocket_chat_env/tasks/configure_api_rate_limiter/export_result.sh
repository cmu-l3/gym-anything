#!/bin/bash
set -euo pipefail

echo "=== Exporting Configure API Rate Limiter Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current settings from Rocket.Chat API
echo "Querying final settings..."

# Login again to get fresh token for verification query
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

ENABLED="unknown"
COUNT="unknown"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # Get Enable Status
  RESP_ENABLE=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/API_Enable_Rate_Limiter" 2>/dev/null || true)
  ENABLED=$(echo "$RESP_ENABLE" | jq -r '.value // empty')

  # Get Count Value
  RESP_COUNT=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/API_Default_Count" 2>/dev/null || true)
  COUNT=$(echo "$RESP_COUNT" | jq -r '.value // empty')
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "rate_limiter_enabled": "$ENABLED",
    "api_default_count": "$COUNT",
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported data:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="