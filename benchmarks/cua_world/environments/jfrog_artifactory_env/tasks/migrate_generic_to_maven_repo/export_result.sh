#!/bin/bash
echo "=== Exporting Migration Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Target Repository exists and is Maven
echo "Checking target repository 'libs-commons-local'..."
TARGET_REPO_INFO=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/repositories/libs-commons-local")

# Parse JSON for existence and type
# Check if key exists in response (OSS returns 400 for detail config sometimes, 
# so we check list or try to deduce from response)
# Actually, the most reliable way in OSS 7.x to check type is fetching the repo list 
# or checking storage info if config is restricted.
# But let's try the config endpoint first, falling back to list.

REPO_LIST=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/repositories")
TARGET_EXISTS=$(echo "$REPO_LIST" | grep -q "libs-commons-local" && echo "true" || echo "false")
TARGET_TYPE=$(echo "$REPO_LIST" | python3 -c "
import sys, json
try:
    repos = json.load(sys.stdin)
    repo = next((r for r in repos if r['key'] == 'libs-commons-local'), None)
    if repo:
        print(repo.get('packageType', 'unknown').lower())
    else:
        print('none')
except:
    print('error')
")

# 2. Check if Source Repository 'temp-uploads' is deleted
echo "Checking source repository 'temp-uploads'..."
SOURCE_EXISTS=$(echo "$REPO_LIST" | grep -q "temp-uploads" && echo "true" || echo "false")

# 3. Check Artifact Migration (Data Integrity)
# We need to verify the artifact exists in the NEW location
ARTIFACT_PATH="org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
NEW_ARTIFACT_URL="http://localhost:8082/artifactory/libs-commons-local/$ARTIFACT_PATH"

ARTIFACT_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password "$NEW_ARTIFACT_URL")
ARTIFACT_EXISTS="false"
if [ "$ARTIFACT_HTTP_CODE" == "200" ]; then
    ARTIFACT_EXISTS="true"
fi

# 4. Check timestamps (Anti-gaming)
# Get artifact creation/last-modified time in new repo
ARTIFACT_INFO=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/storage/libs-commons-local/$ARTIFACT_PATH")
# We can try to parse 'created' or 'lastModified' from this JSON, 
# but simply checking if it exists is the main check since it didn't exist before.
# Since we deleted the repo in setup, any existence in the new repo is fresh.

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_repo_exists": $TARGET_EXISTS,
    "target_repo_type": "$TARGET_TYPE",
    "source_repo_exists": $SOURCE_EXISTS,
    "artifact_exists_in_target": $ARTIFACT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
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