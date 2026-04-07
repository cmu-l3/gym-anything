#!/bin/bash
set -euo pipefail

echo "=== Exporting setup_google_login results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Authenticate to API to fetch final settings
# We need to get the token again to query the settings
LOGIN_JSON=$(curl -s -X POST "${ROCKETCHAT_BASE_URL}/api/v1/login" \
  -H "Content-Type: application/json" \
  -d "{\"user\": \"$ROCKETCHAT_TASK_USERNAME\", \"password\": \"$ROCKETCHAT_TASK_PASSWORD\"}")

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken')
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo "WARNING: Could not authenticate to export results. User may have changed credentials (unlikely but possible)."
    # We will output a result with "api_access": false
    cat > /tmp/task_result.json << EOF
{
    "api_access": false,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
    exit 0
fi

# 4. Query the specific settings
get_setting() {
    local key="$1"
    curl -s -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/settings/$key"
}

SETTING_ENABLE=$(get_setting "Accounts_OAuth_Google")
SETTING_ID=$(get_setting "Accounts_OAuth_Google_id")
SETTING_SECRET=$(get_setting "Accounts_OAuth_Google_secret")

# 5. Construct JSON Result
# We extract values and updated_at timestamps using jq
# Note: Rocket.Chat settings API returns ISO timestamps (e.g., "2026-03-08T12:00:00.000Z")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "api_access": true,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "settings": {
        "enable": $SETTING_ENABLE,
        "id": $SETTING_ID,
        "secret": $SETTING_SECRET
    }
}
EOF

# Move to final location (handling permissions)
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "=== Export complete ==="