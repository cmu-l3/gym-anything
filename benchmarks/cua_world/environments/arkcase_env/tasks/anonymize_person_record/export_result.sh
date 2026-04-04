#!/bin/bash
echo "=== Exporting anonymize_person_record result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PERSON_ID=$(cat /tmp/target_person_id.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Verifying Person ID: $PERSON_ID"

# Query ArkCase API for the current state of the person
PERSON_DATA="{}"
API_SUCCESS="false"

if [ -n "$PERSON_ID" ]; then
    # Try plugin endpoint first
    RESPONSE=$(curl -sk -X GET \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Accept: application/json" \
        "${ARKCASE_URL}/api/v1/plugin/cpr/person/${PERSON_ID}" 2>/dev/null)
    
    # Check if we got valid JSON
    if echo "$RESPONSE" | grep -q "firstName"; then
        PERSON_DATA="$RESPONSE"
        API_SUCCESS="true"
    else
        # Try service endpoint fallback
        RESPONSE=$(curl -sk -X GET \
            -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
            -H "Accept: application/json" \
            "${ARKCASE_URL}/api/v1/service/people/${PERSON_ID}" 2>/dev/null)
        if echo "$RESPONSE" | grep -q "firstName"; then
            PERSON_DATA="$RESPONSE"
            API_SUCCESS="true"
        fi
    fi
fi

# Parse the fields using Python for safety
# We extract just the fields we need to avoid massive JSON dump
PARSED_RESULT=$(python3 << EOF
import sys, json
try:
    data = json.loads('''$PERSON_DATA''')
    result = {
        "exists": True,
        "id": data.get("id", data.get("personId", "")),
        "firstName": data.get("firstName", ""),
        "lastName": data.get("lastName", ""),
        "email": data.get("email"),
        "businessPhone": data.get("businessPhone"),
        "mobilePhone": data.get("mobilePhone")
    }
except Exception as e:
    result = {
        "exists": False,
        "error": str(e)
    }
print(json.dumps(result))
EOF
)

# App status check
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_person_id": "$PERSON_ID",
    "api_success": $API_SUCCESS,
    "person_data": $PARSED_RESULT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="