#!/bin/bash
echo "=== Exporting block_snapshot_artifacts results ==="

source /workspace/scripts/task_utils.sh

REPO_KEY="example-repo-local"
SNAPSHOT_FILE="verification-1.0-SNAPSHOT.jar"
RELEASE_FILE="verification-1.0.jar"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final configuration
echo "Fetching final repository configuration..."
REPO_CONFIG=$(get_repo_info "$REPO_KEY")
echo "$REPO_CONFIG" > /tmp/final_repo_config.json

# Extract excludes pattern using python
EXCLUDES_PATTERN=$(echo "$REPO_CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('excludesPattern', ''))" 2>/dev/null)
echo "Final Excludes Pattern: '$EXCLUDES_PATTERN'"

# 2. Perform Functional Tests (Upload Attempts)
# Create dummy JAR files (valid zip structure to avoid format errors)
echo "Creating dummy artifacts..."
python3 -c "import zipfile; zipfile.ZipFile('$SNAPSHOT_FILE', 'w').close(); zipfile.ZipFile('$RELEASE_FILE', 'w').close()"

# TEST A: Upload Snapshot (Should FAIL if task is successful)
echo "Test A: Attempting to upload $SNAPSHOT_FILE (Expect Failure)..."
HTTP_SNAPSHOT=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${SNAPSHOT_FILE}" \
    -T "$SNAPSHOT_FILE")
echo "HTTP Status for Snapshot Upload: $HTTP_SNAPSHOT"

# TEST B: Upload Release (Should SUCCEED)
echo "Test B: Attempting to upload $RELEASE_FILE (Expect Success)..."
HTTP_RELEASE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${RELEASE_FILE}" \
    -T "$RELEASE_FILE")
echo "HTTP Status for Release Upload: $HTTP_RELEASE"

# Clean up local test files
rm -f "$SNAPSHOT_FILE" "$RELEASE_FILE"

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "repo_key": "$REPO_KEY",
    "excludes_pattern": "$EXCLUDES_PATTERN",
    "snapshot_upload_http_status": $HTTP_SNAPSHOT,
    "release_upload_http_status": $HTTP_RELEASE,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="