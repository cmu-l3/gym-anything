#!/bin/bash
# Export results for prime_remote_proxy_cache task
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPO_KEY="central-proxy-test"
ARTIFACT_PATH="org/apache/commons/commons-collections4/4.4/commons-collections4-4.4.jar"

# 1. Get Repository Configuration (Config Check)
# Note: Using python to parse the list because OSS often restricts individual GET /api/repositories/{key}
echo "Checking repository configuration..."
REPO_CONFIG=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/repositories" | python3 -c "
import sys, json
try:
    repos = json.load(sys.stdin)
    target = next((r for r in repos if r['key'] == '$REPO_KEY'), None)
    if target:
        print(json.dumps(target))
    else:
        print('{}')
except Exception as e:
    print('{}')
")

# 2. Check Artifact Existence in Cache (Proof of Work)
# We check the storage API for the specific artifact in the specific repo
echo "Checking artifact status in storage..."
ARTIFACT_INFO=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/storage/$REPO_KEY/$ARTIFACT_PATH")

# 3. Parse Artifact Details
# We need to know if it exists (no 404) and its size
ARTIFACT_EXISTS="false"
ARTIFACT_SIZE="0"
ARTIFACT_CREATED_TIME="0"

if echo "$ARTIFACT_INFO" | grep -q "\"uri\""; then
    # It seems to be a valid response
    if ! echo "$ARTIFACT_INFO" | grep -q "\"errors\""; then
        ARTIFACT_EXISTS="true"
        # Extract size
        ARTIFACT_SIZE=$(echo "$ARTIFACT_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('size', 0))" 2>/dev/null || echo "0")
        
        # Extract creation time to verify it was done during task
        # Format example: "2024-05-20T10:00:00.000Z"
        CREATED_STR=$(echo "$ARTIFACT_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('created', ''))" 2>/dev/null)
        if [ -n "$CREATED_STR" ]; then
            ARTIFACT_CREATED_TIME=$(date -d "$CREATED_STR" +%s 2>/dev/null || echo "0")
        fi
    fi
fi

# 4. Check if a screenshot of the artifact browser was taken (Agent evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "repo_config": $REPO_CONFIG,
    "artifact_verification": {
        "exists": $ARTIFACT_EXISTS,
        "size_bytes": $ARTIFACT_SIZE,
        "created_timestamp": $ARTIFACT_CREATED_TIME,
        "path": "$ARTIFACT_PATH",
        "repo": "$REPO_KEY"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="