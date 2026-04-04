#!/bin/bash
echo "=== Exporting generate_access_token results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/ci_access_token.txt"

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
AUTH_SUCCESS="false"
AUTH_HTTP_CODE="0"
TOKEN_CONTENT_PREVIEW=""

# Check file existence and metadata
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read token (trim whitespace)
    TOKEN=$(cat "$OUTPUT_FILE" | tr -d '\n' | tr -d '\r' | xargs)
    
    # Create a safe preview (first 5 chars ... last 5 chars)
    TOKEN_LEN=${#TOKEN}
    if [ "$TOKEN_LEN" -gt 10 ]; then
        TOKEN_CONTENT_PREVIEW="${TOKEN:0:5}...${TOKEN: -5}"
    else
        TOKEN_CONTENT_PREVIEW="[Too short]"
    fi

    # VALIDATE TOKEN: Try to authenticate against Artifactory
    # We do this here inside the container to avoid networking issues with the verifier
    if [ -n "$TOKEN" ]; then
        echo "Testing token authentication..."
        AUTH_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $TOKEN" \
            "http://localhost:8082/artifactory/api/system/ping")
        
        echo "Auth check HTTP code: $AUTH_HTTP_CODE"
        
        if [ "$AUTH_HTTP_CODE" = "200" ]; then
            AUTH_SUCCESS="true"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "token_auth_success": $AUTH_SUCCESS,
    "token_auth_http_code": "$AUTH_HTTP_CODE",
    "token_preview": "$TOKEN_CONTENT_PREVIEW",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="