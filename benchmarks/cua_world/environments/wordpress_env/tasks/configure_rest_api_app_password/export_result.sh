#!/bin/bash
# Export script for configure_rest_api_app_password task (post_task hook)

echo "=== Exporting REST API Configuration result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check credentials file
FILE_EXISTS="false"
CRED_STRING=""
CRED_FILE_PATH="/home/ga/mobile_api_credentials.txt"

if [ -f "$CRED_FILE_PATH" ]; then
    FILE_EXISTS="true"
    # Extract the first line and remove whitespace/newlines
    CRED_STRING=$(cat "$CRED_FILE_PATH" | head -n 1 | tr -d '\n' | tr -d '\r')
    echo "Found credentials file."
else
    echo "Credentials file not found."
fi

# 2. Check Database for Application Password
APP_PWD_EXISTS="false"
APP_PWD_META=$(wp_db_query "SELECT meta_value FROM wp_usermeta WHERE user_id=1 AND meta_key='_application_passwords'" 2>/dev/null || echo "")

if echo "$APP_PWD_META" | grep -q "MobileApp_iOS"; then
    APP_PWD_EXISTS="true"
    echo "Application Password 'MobileApp_iOS' found in database."
else
    echo "Application Password 'MobileApp_iOS' NOT found in database."
fi

# 3. Check Database for Post
POST_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='App Configuration Endpoint' AND post_type='post' ORDER BY ID DESC LIMIT 1" 2>/dev/null || echo "")
POST_STATUS=""
POST_CONTENT=""

if [ -n "$POST_ID" ]; then
    POST_STATUS=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$POST_ID" 2>/dev/null || echo "")
    POST_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$POST_ID" 2>/dev/null || echo "")
    echo "Found post ID $POST_ID with status '$POST_STATUS'."
else
    echo "Post 'App Configuration Endpoint' NOT found in database."
fi

# 4. Perform ACTUAL API TEST (Ultimate anti-gaming validation)
API_HTTP_CODE=0
API_RESPONSE=""

if [ -n "$CRED_STRING" ] && [[ "$CRED_STRING" == admin:* ]]; then
    echo "Testing REST API authentication with provided credentials..."
    # WordPress REST API private posts endpoint
    API_URL="http://localhost/wp-json/wp/v2/posts?status=private&search=App+Configuration+Endpoint"
    
    # Run curl with basic auth, output HTTP status to variable, and body to file
    API_HTTP_CODE=$(curl -s -o /tmp/api_response.json -w "%{http_code}" -u "$CRED_STRING" "$API_URL")
    
    echo "API HTTP Code: $API_HTTP_CODE"
    
    if [ -f /tmp/api_response.json ]; then
        # Use jq to safely escape the JSON response into a string for embedding
        if command -v jq >/dev/null 2>&1; then
            API_RESPONSE=$(jq -Rs . < /tmp/api_response.json | sed 's/^"//;s/"$//')
        else
            # Fallback if jq is missing
            API_RESPONSE=$(cat /tmp/api_response.json | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r' | head -c 5000)
        fi
    fi
else
    echo "Skipping API test - credentials string missing or invalid format (must start with 'admin:')."
fi

# Prepare sanitized content for export
SAFE_CRED_STRING=$(echo "$CRED_STRING" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
SAFE_POST_CONTENT=$(echo "$POST_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r' | head -c 1000)

# Create JSON Result Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "cred_string": "$SAFE_CRED_STRING",
    "app_pwd_exists": $APP_PWD_EXISTS,
    "post_id": "${POST_ID:-}",
    "post_status": "${POST_STATUS:-}",
    "post_content": "$SAFE_POST_CONTENT",
    "api_http_code": $API_HTTP_CODE,
    "api_response": "$API_RESPONSE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final destination
rm -f /tmp/rest_api_task_result.json 2>/dev/null || sudo rm -f /tmp/rest_api_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rest_api_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rest_api_task_result.json
chmod 666 /tmp/rest_api_task_result.json 2>/dev/null || sudo chmod 666 /tmp/rest_api_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/rest_api_task_result.json"
echo "=== Export complete ==="