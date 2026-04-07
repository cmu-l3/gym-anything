#!/bin/bash
set -euo pipefail

echo "=== Exporting Configure SMTP Settings Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch current settings via API
echo "Fetching final settings from API..."

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Default values if fetch fails
VAL_PROTOCOL=""
VAL_HOST=""
VAL_PORT=""
VAL_IGNORE_TLS="false"
SETTINGS_FOUND="false"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
    SETTINGS_FOUND="true"
    
    # Helper to get setting value
    get_setting() {
        local key="$1"
        curl -sS \
          -H "X-Auth-Token: $AUTH_TOKEN" \
          -H "X-User-Id: $USER_ID" \
          "${ROCKETCHAT_BASE_URL}/api/v1/settings/$key" 2>/dev/null | jq -r '.value // empty'
    }

    VAL_PROTOCOL=$(get_setting "SMTP_Protocol")
    VAL_HOST=$(get_setting "SMTP_Host")
    VAL_PORT=$(get_setting "SMTP_Port")
    VAL_IGNORE_TLS=$(get_setting "SMTP_IgnoreTLS")
else
    echo "ERROR: Failed to login to API to check settings."
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "settings_found": $SETTINGS_FOUND,
    "values": {
        "SMTP_Protocol": "$VAL_PROTOCOL",
        "SMTP_Host": "$VAL_HOST",
        "SMTP_Port": "$VAL_PORT",
        "SMTP_IgnoreTLS": $VAL_IGNORE_TLS
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="