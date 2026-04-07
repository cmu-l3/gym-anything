#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_message_auditing results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get API Token for verification
if ! api_login "admin" "Admin1234!"; then
  echo "ERROR: Failed to login to API for verification"
  # Create a failure result file
  cat > /tmp/task_result.json << EOF
{
  "api_access_failed": true,
  "error": "Could not log in to verify settings"
}
EOF
  exit 0
fi

AUTH_TOKEN=$(echo "$response" | jq -r '.data.authToken')
USER_ID=$(echo "$response" | jq -r '.data.userId')

# 3. Fetch Current Settings
get_setting() {
  local key="$1"
  curl -s \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/$key" | jq -r '.value'
}

READ_RECEIPT=$(get_setting "Message_Read_Receipt_Enabled")
ALLOW_EDIT=$(get_setting "Message_AllowEditing")
BLOCK_EDIT=$(get_setting "Message_AllowEditing_BlockEditInMinutes")
ALLOW_DELETE=$(get_setting "Message_AllowDeleting")

# 4. Check timestamps (Anti-gaming)
# We check if settings were updated AFTER task start.
# The API returns _updatedAt for settings, but we need to query the full object.
# For simplicity, we compare values against the recorded initial state in the verifier,
# or we can rely on value changes since we forced defaults in setup.

# 5. Create Result JSON
# Use a temp file to avoid permission issues during write
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
  "final_settings": {
    "Message_Read_Receipt_Enabled": $READ_RECEIPT,
    "Message_AllowEditing": $ALLOW_EDIT,
    "Message_AllowEditing_BlockEditInMinutes": $BLOCK_EDIT,
    "Message_AllowDeleting": $ALLOW_DELETE
  },
  "initial_settings_path": "/tmp/initial_settings_state.json",
  "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
  "export_timestamp": $(date +%s)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="