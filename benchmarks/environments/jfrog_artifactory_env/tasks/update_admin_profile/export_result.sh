#!/bin/bash
# Export script for update_admin_profile task
# Collects file data and API state into a JSON for the verifier

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Timestamp Check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. File Verification (Agent Output)
OUTPUT_FILE="/home/ga/encrypted_password.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MODIFIED_TIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | tr -d '\n')
    FILE_MODIFIED_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MODIFIED_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. API Verification (Ground Truth)
# Retrieve current user details for 'admin'
# Note: In OSS, GET /api/security/users/admin is usually allowed even if POST is not.
echo "Querying Artifactory API for admin user details..."
API_USER_JSON=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/security/users/admin")

# Extract email using python (since jq might be finicky with error output)
CURRENT_EMAIL=$(echo "$API_USER_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('email', ''))" 2>/dev/null || echo "")

# Retrieve the actual encrypted password for comparison
echo "Querying Artifactory API for encrypted password..."
ACTUAL_ENCRYPTED_PASS=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/security/encryptedPassword")

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": "$FILE_CONTENT",
    "api_email": "$CURRENT_EMAIL",
    "api_encrypted_password": "$ACTUAL_ENCRYPTED_PASS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (permissions safe)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="