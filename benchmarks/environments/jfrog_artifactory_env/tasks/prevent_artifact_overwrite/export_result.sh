#!/bin/bash
# Export results for prevent_artifact_overwrite task
set -e

echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ARTIFACT_PATH="org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
NEW_ARTIFACT_PATH="org/apache/commons/commons-io/2.15.1/test-new-file.txt"

# 1. Test: Attempt to OVERWRITE the existing artifact
# This should FAIL (403/409) if the agent succeeded.
echo "Testing artifact overwrite..."
OVERWRITE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    -X PUT \
    -d "Malicious Overwrite Content" \
    "http://localhost:8082/artifactory/example-repo-local/$ARTIFACT_PATH")

echo "Overwrite attempt HTTP code: $OVERWRITE_HTTP"

# 2. Test: Attempt to deploy a NEW artifact
# This should SUCCEED (201) to prove the repo is not just Read-Only.
echo "Testing new artifact deployment..."
NEW_DEPLOY_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    -X PUT \
    -d "New Valid Content" \
    "http://localhost:8082/artifactory/example-repo-local/$NEW_ARTIFACT_PATH")

echo "New deployment attempt HTTP code: $NEW_DEPLOY_HTTP"

# 3. Check if the original artifact still exists (Integrity check)
echo "Checking artifact integrity..."
EXISTENCE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    -I \
    "http://localhost:8082/artifactory/example-repo-local/$ARTIFACT_PATH")

ARTIFACT_EXISTS="false"
if [ "$EXISTENCE_HTTP" == "200" ]; then
    ARTIFACT_EXISTS="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "overwrite_http_code": $OVERWRITE_HTTP,
    "new_deploy_http_code": $NEW_DEPLOY_HTTP,
    "artifact_exists": $ARTIFACT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="