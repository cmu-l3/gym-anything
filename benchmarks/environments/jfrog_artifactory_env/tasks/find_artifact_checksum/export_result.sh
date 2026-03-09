#!/bin/bash
echo "=== Exporting find_artifact_checksum results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# 2. Analyze Output File
OUTPUT_FILE="/home/ga/artifact_checksum.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | tr -d '[:space:]') # Strip whitespace
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Retrieve Authoritative Data from Artifactory
# We query the API *now* to ensure we verify against the current state of the server
REPO="example-repo-local"
ARTIFACT_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
API_URL="${ARTIFACTORY_URL}/artifactory/api/storage/${REPO}/${ARTIFACT_PATH}"

echo "Querying Artifactory for authoritative checksum..."
API_RESPONSE=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "$API_URL")
AUTHORITATIVE_SHA256=$(echo "$API_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('checksums', {}).get('sha256', ''))" 2>/dev/null || echo "")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "submitted_content": "$FILE_CONTENT",
    "authoritative_sha256": "$AUTHORITATIVE_SHA256",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save Result safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="