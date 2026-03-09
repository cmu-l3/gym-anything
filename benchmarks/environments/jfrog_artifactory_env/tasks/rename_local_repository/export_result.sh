#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Target Repo Exists
TARGET_REPO_EXISTS="false"
if repo_exists "module-core-local"; then
    TARGET_REPO_EXISTS="true"
fi

# 2. Check if Source Repo Exists (Should be deleted)
SOURCE_REPO_EXISTS="true"
if ! repo_exists "legacy-dev-local"; then
    SOURCE_REPO_EXISTS="false"
fi

# 3. Check if Artifact Exists in Target Repo
ARTIFACT_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
ARTIFACT_MIGRATED="false"
ARTIFACT_SIZE="0"

# Use curl to check file existence (HTTP 200)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password \
    "http://localhost:8082/artifactory/module-core-local/$ARTIFACT_PATH")

if [ "$HTTP_STATUS" == "200" ]; then
    ARTIFACT_MIGRATED="true"
    # Get file info (size)
    FILE_INFO=$(curl -s -u admin:password -X GET "http://localhost:8082/artifactory/api/storage/module-core-local/$ARTIFACT_PATH")
    ARTIFACT_SIZE=$(echo "$FILE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('size', 0))" 2>/dev/null || echo "0")
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
cat <<EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_repo_exists": $TARGET_REPO_EXISTS,
    "source_repo_exists": $SOURCE_REPO_EXISTS,
    "artifact_migrated": $ARTIFACT_MIGRATED,
    "artifact_size_bytes": $ARTIFACT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json