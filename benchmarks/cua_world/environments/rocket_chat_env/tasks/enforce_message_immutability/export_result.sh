#!/bin/bash
set -euo pipefail

echo "=== Exporting enforce_message_immutability result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Authenticate to API to check settings
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

RC_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
RC_USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$RC_TOKEN" ]; then
  echo "ERROR: Could not authenticate to export results"
  # Dump empty result to avoid verifier crash, but set success false
  echo '{"error": "auth_failed"}' > /tmp/task_result.json
  exit 0
fi

get_setting() {
  local id="$1"
  curl -sS -H "X-Auth-Token: $RC_TOKEN" -H "X-User-Id: $RC_USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/$id" 2>/dev/null | jq -r '.value'
}

# Fetch final values
VAL_DELETING=$(get_setting "Message_AllowDeleting")
VAL_EDITING=$(get_setting "Message_AllowEditing")
VAL_BLOCK_MIN=$(get_setting "Message_AllowEditing_BlockEditInMinutes")
VAL_HISTORY=$(get_setting "Message_KeepHistory")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "allow_deleting": $VAL_DELETING,
  "allow_editing": $VAL_EDITING,
  "block_edit_minutes": $VAL_BLOCK_MIN,
  "keep_history": $VAL_HISTORY,
  "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result:"
cat /tmp/task_result.json
echo "=== Export complete ==="