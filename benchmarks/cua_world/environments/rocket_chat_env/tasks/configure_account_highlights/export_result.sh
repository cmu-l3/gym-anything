#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_account_highlights results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
echo "$TASK_END" > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the Rocket.Chat API to get the user's current preferences
# We need to log in again to get a fresh token (or reuse one if we stored it, but fresh is safer)
LOGIN_JSON=$(curl -s -X POST \
    -H "Content-type: application/json" \
    -d "{\"user\": \"$ROCKETCHAT_TASK_USERNAME\", \"password\": \"$ROCKETCHAT_TASK_PASSWORD\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/login")

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken')
USER_ID=$(echo "$LOGIN_JSON" | jq -r '.data.userId')
HIGHLIGHTS_DATA="[]"
API_SUCCESS="false"

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo "Fetching user preferences..."
    PREFS_JSON=$(curl -s -X GET \
        -H "X-Auth-Token: $TOKEN" \
        -H "X-User-Id: $USER_ID" \
        "${ROCKETCHAT_BASE_URL}/api/v1/users.getPreferences")
    
    # Extract the highlights field. It might be an array or a comma-separated string depending on RC version.
    # We'll save the raw value of the 'highlights' key.
    HIGHLIGHTS_DATA=$(echo "$PREFS_JSON" | jq -c '.preferences.highlights // []')
    API_SUCCESS="true"
else
    echo "ERROR: Failed to authenticate to retrieve results."
fi

# Create result JSON
# We use a temp file and move it to avoid permission issues with the agent user
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "api_success": $API_SUCCESS,
    "highlights": $HIGHLIGHTS_DATA,
    "task_end_timestamp": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="