#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_privilege result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if privilege exists via API
PRIV_NAME="View Triage Queue"
encoded_name=$(echo "$PRIV_NAME" | sed 's/ /%20/g')

# Fetch privilege details
RESPONSE=$(curl -sk \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/privilege/${encoded_name}?v=full" 2>/dev/null || echo "{}")

# Check if it was found (API returns 404/error if not found, or a json object if found)
# We can check if the UUID field exists in the response
EXISTS=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print('true' if 'uuid' in data else 'false')
except:
    print('false')
")

DESCRIPTION=""
if [ "$EXISTS" = "true" ]; then
    DESCRIPTION=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('description', ''))
except:
    print('')
")
fi

# Check initial state record
INITIAL_EXISTS="false"
if [ -f /tmp/initial_privilege_exists.txt ]; then
    INITIAL_EXISTS=$(cat /tmp/initial_privilege_exists.txt)
fi

# Check if browser is running
APP_RUNNING="false"
if pgrep -f "epiphany" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "privilege_exists": $EXISTS,
    "privilege_name": "$PRIV_NAME",
    "privilege_description": "$(echo "$DESCRIPTION" | sed 's/"/\\"/g')",
    "initial_exists": $INITIAL_EXISTS,
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="