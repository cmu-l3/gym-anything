#!/bin/bash
# Export script for Create API Token task
# Verifies file existence, content, timestamps, and validity of the token

echo "=== Exporting Create API Token Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TOKEN_FILE="/home/ga/api_token.txt"
JOBS_FILE="/home/ga/jenkins_jobs.json"
EXPECTED_TOKEN_NAME="automation-token"

# 1. Verify Token File
TOKEN_FILE_EXISTS="false"
TOKEN_CREATED_DURING_TASK="false"
TOKEN_VALUE=""
TOKEN_AUTHENTICATES="false"
HTTP_STATUS=0

if [ -f "$TOKEN_FILE" ]; then
    TOKEN_FILE_EXISTS="true"
    # Read token (trim whitespace)
    TOKEN_VALUE=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
    
    # Check timestamp
    TOKEN_MTIME=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || echo "0")
    if [ "$TOKEN_MTIME" -gt "$TASK_START" ]; then
        TOKEN_CREATED_DURING_TASK="true"
    fi

    # Verify token authentication
    if [ -n "$TOKEN_VALUE" ]; then
        echo "Attempting to authenticate with captured token..."
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "admin:$TOKEN_VALUE" "$JENKINS_URL/api/json")
        echo "Auth check HTTP status: $HTTP_STATUS"
        if [ "$HTTP_STATUS" -eq 200 ]; then
            TOKEN_AUTHENTICATES="true"
        fi
    fi
fi

# 2. Verify Jobs JSON File
JOBS_FILE_EXISTS="false"
JOBS_FILE_VALID="false"
JOBS_CREATED_DURING_TASK="false"
JOBS_COUNT_IN_FILE=0
JOBS_MATCH_ACTUAL="false"

if [ -f "$JOBS_FILE" ]; then
    JOBS_FILE_EXISTS="true"
    
    # Check timestamp
    JOBS_MTIME=$(stat -c %Y "$JOBS_FILE" 2>/dev/null || echo "0")
    if [ "$JOBS_MTIME" -gt "$TASK_START" ]; then
        JOBS_CREATED_DURING_TASK="true"
    fi

    # Validate JSON content
    if jq -e . "$JOBS_FILE" >/dev/null 2>&1; then
        JOBS_FILE_VALID="true"
        
        # Count jobs in the file
        JOBS_COUNT_IN_FILE=$(jq '.jobs | length' "$JOBS_FILE" 2>/dev/null || echo "0")
        
        # Get actual job count
        ACTUAL_COUNT=$(count_jobs)
        
        if [ "$JOBS_COUNT_IN_FILE" -eq "$ACTUAL_COUNT" ]; then
            JOBS_MATCH_ACTUAL="true"
        fi
    fi
fi

# 3. Verify Token Name in Jenkins Config (Anti-gaming)
# We need to find the admin user's config file inside the container
# The user ID might be 'admin' or something like 'admin_123456'
TOKEN_NAME_FOUND="false"

# Find admin config file
ADMIN_CONFIG_FILE=$(find /home/ga/jenkins/jenkins_home/users -name "config.xml" | xargs grep -l "<fullName>admin</fullName>" | head -1)

if [ -n "$ADMIN_CONFIG_FILE" ]; then
    echo "Found admin config at: $ADMIN_CONFIG_FILE"
    # Check if the token name exists in the config (hashed value is stored, but name is plain)
    if grep -q "<name>$EXPECTED_TOKEN_NAME</name>" "$ADMIN_CONFIG_FILE"; then
        TOKEN_NAME_FOUND="true"
        echo "Found token name '$EXPECTED_TOKEN_NAME' in user config."
    else
        echo "Token name '$EXPECTED_TOKEN_NAME' NOT found in user config."
    fi
else
    echo "WARNING: Could not locate admin user config file."
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "token_file": {
        "exists": $TOKEN_FILE_EXISTS,
        "created_during_task": $TOKEN_CREATED_DURING_TASK,
        "content_length": ${#TOKEN_VALUE},
        "authenticates": $TOKEN_AUTHENTICATES,
        "http_status": $HTTP_STATUS
    },
    "jobs_file": {
        "exists": $JOBS_FILE_EXISTS,
        "created_during_task": $JOBS_CREATED_DURING_TASK,
        "valid_json": $JOBS_FILE_VALID,
        "jobs_count": $JOBS_COUNT_IN_FILE,
        "matches_actual_count": $JOBS_MATCH_ACTUAL
    },
    "jenkins_config": {
        "token_name_found": $TOKEN_NAME_FOUND
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="