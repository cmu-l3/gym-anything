#!/bin/bash
echo "=== Exporting create_user_account task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(db_query "SELECT COUNT(*) FROM auth_user;" 2>/dev/null | xargs || echo "0")

# Check if the target user exists
USER_EXISTS_COUNT=$(db_query "SELECT COUNT(*) FROM auth_user WHERE username='maria_santos';" 2>/dev/null | xargs || echo "0")

FIRST_NAME=""
LAST_NAME=""
EMAIL=""
IS_ACTIVE="f"
DATE_JOINED="0"

if [ "$USER_EXISTS_COUNT" -ge 1 ] 2>/dev/null; then
    USER_EXISTS="true"
    FIRST_NAME=$(db_query "SELECT first_name FROM auth_user WHERE username='maria_santos';" 2>/dev/null | xargs)
    LAST_NAME=$(db_query "SELECT last_name FROM auth_user WHERE username='maria_santos';" 2>/dev/null | xargs)
    EMAIL=$(db_query "SELECT email FROM auth_user WHERE username='maria_santos';" 2>/dev/null | xargs)
    IS_ACTIVE=$(db_query "SELECT is_active FROM auth_user WHERE username='maria_santos';" 2>/dev/null | xargs)
    DATE_JOINED=$(db_query "SELECT EXTRACT(EPOCH FROM date_joined)::int FROM auth_user WHERE username='maria_santos';" 2>/dev/null | xargs)
else
    USER_EXISTS="false"
fi

# Check if the password works by obtaining an API token
AUTH_RESPONSE=$(curl -s -L -X POST "${WGER_URL}/api/v2/token" \
    -H 'Content-Type: application/json' \
    -d '{"username": "maria_santos", "password": "TrainerPass2024!"}' 2>/dev/null)

TOKEN_OBTAINED="false"
TOKEN=$(echo "$AUTH_RESPONSE" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    if d.get('access'):
        print('true')
    else:
        print('false')
except:
    print('false')
" 2>/dev/null)

if [ "$TOKEN" = "true" ]; then
    TOKEN_OBTAINED="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Export the collected metrics to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_user_count": $INITIAL_COUNT,
    "final_user_count": $FINAL_COUNT,
    "user_exists": $USER_EXISTS,
    "first_name": "$FIRST_NAME",
    "last_name": "$LAST_NAME",
    "email": "$EMAIL",
    "is_active": "$IS_ACTIVE",
    "date_joined": ${DATE_JOINED:-0},
    "token_obtained": $TOKEN_OBTAINED,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Ensure safe copy without permissions errors
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete, saved to /tmp/task_result.json"
cat /tmp/task_result.json