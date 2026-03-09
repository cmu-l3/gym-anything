#!/bin/bash
# post_task: Export results for subscribe_case_notifications
# Checks if the subscription exists in ArkCase via API

echo "=== Exporting subscribe_case_notifications results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Case ID
# If setup script saved it, use it. Otherwise, search by title.
CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
CASE_TITLE="Improper Records Retention Complaint"

if [ -z "$CASE_ID" ]; then
    echo "Case ID not found in temp file. Searching by title..."
    # Search API to find ID by title (Mock search logic or assume agent worked on the one they found)
    # For verification reliability, we really need the ID.
    # We'll try to list complaints and filter by title using jq/python if available,
    # or rely on the assumption that if the setup succeeded, the file exists.
    echo "WARNING: Verifier might fail if ID is missing."
fi

# 3. Check Subscription Status via API
IS_SUBSCRIBED="false"
SUBSCRIPTION_DETAILS="{}"

if [ -n "$CASE_ID" ]; then
    echo "Checking subscription for Case ID: $CASE_ID"
    # GET /api/v1/service/subscription/{user}/objType/{type}/objId/{id}
    # If subscribed, returns 200 with JSON. If not, likely 404 or empty.
    
    SUB_RESPONSE=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        "${ARKCASE_URL}/api/v1/service/subscription/${ARKCASE_ADMIN}/objType/COMPLAINT/objId/${CASE_ID}" 2>/dev/null)
    
    # Check if response contains subscription data (e.g. "subscriptionId" or "user")
    if echo "$SUB_RESPONSE" | grep -q "subscriptionId" || echo "$SUB_RESPONSE" | grep -q "\"user\""; then
        IS_SUBSCRIBED="true"
        SUBSCRIPTION_DETAILS="$SUB_RESPONSE"
        echo "Subscription confirmed via API."
    else
        echo "No subscription found via API. Response: $SUB_RESPONSE"
    fi
else
    echo "Cannot verify subscription: Case ID unknown."
fi

# 4. Check Browser State (URL)
# Get current URL from Firefox window title if possible, or just note the app is open
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "is_subscribed": $IS_SUBSCRIBED,
    "subscription_details": $SUBSCRIPTION_DETAILS,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="