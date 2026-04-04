#!/bin/bash
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time and initial bad checksum
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BAD_SHA256=$(cat /tmp/corrupted_sha256.txt 2>/dev/null || echo "")
VALID_SHA256=$(cat /tmp/valid_sha256.txt 2>/dev/null || echo "")

# 3. Query Artifactory for the current artifact status
ARTIFACT_PATH="example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

echo "Querying artifact info..."
# Get storage info (contains checksums)
STORAGE_JSON=$(art_api GET "/api/storage/${ARTIFACT_PATH}")

# Extract SHA256 from JSON response
HOSTED_SHA256=$(echo "$STORAGE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('checksums', {}).get('sha256', 'missing'))" 2>/dev/null || echo "error")

# Check if artifact exists (HTTP 200/404 check via previous curl result logic or explicit check)
ARTIFACT_EXISTS="false"
if [ "$HOSTED_SHA256" != "missing" ] && [ "$HOSTED_SHA256" != "error" ]; then
    ARTIFACT_EXISTS="true"
fi

# 4. Check if the file on Desktop was touched (just for info)
LOCAL_FILE="/home/ga/Desktop/commons-lang3-3.14.0.jar"
LOCAL_ACCESSED="false"
if [ -f "$LOCAL_FILE" ]; then
    # Simple check if access time > start time (imperfect but useful hint)
    ATIME=$(stat -c %X "$LOCAL_FILE")
    if [ "$ATIME" -gt "$TASK_START" ]; then
        LOCAL_ACCESSED="true"
    fi
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "artifact_exists": $ARTIFACT_EXISTS,
    "hosted_sha256": "$HOSTED_SHA256",
    "valid_sha256": "$VALID_SHA256",
    "bad_initial_sha256": "$BAD_SHA256",
    "local_file_accessed": $LOCAL_ACCESSED,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="