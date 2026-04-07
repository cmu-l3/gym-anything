#!/bin/bash
echo "=== Exporting GDPR Data Redaction Result ==="

source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Authenticate via API
ac_login

TARGET_USER_ID=$(cat /tmp/target_user_id.txt 2>/dev/null)
if [ -z "$TARGET_USER_ID" ]; then
    echo "Error: target_user_id.txt not found."
    TARGET_USER_ID="UNKNOWN"
fi

# Query the target user ID to see its final state
# We capture both the HTTP status code (to check if deleted) and the response body
HTTP_STATUS=$(curl -sk -o /tmp/target_user_resp.json -w "%{http_code}" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X GET "${AC_URL}/api/v3/users/${TARGET_USER_ID}")

if [ "$HTTP_STATUS" = "200" ]; then
    TARGET_USER_DATA=$(cat /tmp/target_user_resp.json)
else
    # If 404, the user was deleted
    TARGET_USER_DATA="null"
fi

# Query all users to check if the agent recreated the user or if the original name still exists
ANY_INGRID=$(ac_api GET "/users" | jq -c '[.[] | select((.firstName=="Ingrid" and .lastName=="Sorensen") or .firstName=="Ingrid")]' 2>/dev/null || echo "[]")

# Create JSON result safely
TEMP_JSON=$(mktemp /tmp/redaction_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_user_id": "$TARGET_USER_ID",
    "target_user_status": $HTTP_STATUS,
    "target_user_data": $TARGET_USER_DATA,
    "any_ingrid_remaining": $ANY_INGRID,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="