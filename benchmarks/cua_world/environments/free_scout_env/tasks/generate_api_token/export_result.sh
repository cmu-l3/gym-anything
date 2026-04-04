#!/bin/bash
echo "=== Exporting generate_api_token result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TOKEN_FILE="/home/ga/metrics_token.txt"
EXPECTED_NAME="MetricsDash"

# 1. Check if token file exists and read it
FILE_EXISTS="false"
TOKEN_CONTENT=""
if [ -f "$TOKEN_FILE" ]; then
    FILE_EXISTS="true"
    TOKEN_CONTENT=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
fi

# 2. Functional Test: Verify token works against API
API_STATUS="0"
API_WORKS="false"
if [ -n "$TOKEN_CONTENT" ]; then
    # Test against mailboxes endpoint (usually safe and always exists)
    echo "Testing token against API..."
    API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-FreeScout-API-Key: $TOKEN_CONTENT" "http://localhost:8080/api/mailboxes" || echo "0")
    
    if [ "$API_STATUS" = "200" ]; then
        API_WORKS="true"
    fi
fi

# 3. Database Check: Verify token record exists in DB
# We check for the token name AND that it was created recently
TOKEN_DB_DATA=$(fs_query "SELECT id, name, created_at FROM api_tokens WHERE name = '$EXPECTED_NAME' ORDER BY id DESC LIMIT 1" 2>/dev/null)

DB_TOKEN_FOUND="false"
DB_TOKEN_NAME=""
DB_CREATED_AT=""
IS_NEW="false"

if [ -n "$TOKEN_DB_DATA" ]; then
    DB_TOKEN_FOUND="true"
    DB_TOKEN_NAME=$(echo "$TOKEN_DB_DATA" | cut -f2)
    DB_CREATED_AT=$(echo "$TOKEN_DB_DATA" | cut -f3)
    
    # Convert DB timestamp to seconds
    DB_TS=$(date -d "$DB_CREATED_AT" +%s 2>/dev/null || echo "0")
    
    # Check if created after task start
    if [ "$DB_TS" -ge "$TASK_START" ]; then
        IS_NEW="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "token_content_length": ${#TOKEN_CONTENT},
    "api_status_code": $API_STATUS,
    "api_works": $API_WORKS,
    "db_token_found": $DB_TOKEN_FOUND,
    "db_token_name": "$DB_TOKEN_NAME",
    "db_created_at": "$DB_CREATED_AT",
    "is_newly_created": $IS_NEW,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="