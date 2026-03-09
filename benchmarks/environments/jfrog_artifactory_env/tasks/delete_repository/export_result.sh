#!/bin/bash
# Export script for delete_repository task
echo "=== Exporting delete_repository results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check current state of repositories
TARGET_REPO="helix-staging-local"
DEFAULT_REPO="example-repo-local"
ARTIFACT_PATH="$TARGET_REPO/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

# Check if target repo still exists
if repo_exists "$TARGET_REPO"; then
    TARGET_EXISTS="true"
else
    TARGET_EXISTS="false"
fi

# Check if default repo still exists (Collateral damage check)
if repo_exists "$DEFAULT_REPO"; then
    DEFAULT_EXISTS="true"
else
    DEFAULT_EXISTS="false"
fi

# Check if artifact is accessible (should be 404 if repo deleted)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password "http://localhost:8082/artifactory/$ARTIFACT_PATH")
if [ "$HTTP_CODE" = "200" ]; then
    ARTIFACT_EXISTS="true"
else
    ARTIFACT_EXISTS="false"
fi

# 3. Retrieve initial state info
INITIAL_TARGET_EXISTS=$(cat /tmp/initial_target_exists 2>/dev/null || echo "false")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_repo": "$TARGET_REPO",
    "target_exists_final": $TARGET_EXISTS,
    "target_exists_initial": $INITIAL_TARGET_EXISTS,
    "default_repo_exists": $DEFAULT_EXISTS,
    "artifact_exists": $ARTIFACT_EXISTS,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="