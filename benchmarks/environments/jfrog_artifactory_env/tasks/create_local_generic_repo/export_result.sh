#!/bin/bash
echo "=== Exporting create_local_generic_repo results ==="

source /workspace/scripts/task_utils.sh

# Timestamp info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Repository Information
echo "Querying repository list..."
REPO_INFO="{}"
REPO_EXISTS="false"
REPO_TYPE="unknown"
PACKAGE_TYPE="unknown"

# Get list of all repos and filter for our target
# We use python to parse the JSON list safely
REPO_DATA=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/repositories")
if [ -n "$REPO_DATA" ]; then
    REPO_INFO=$(echo "$REPO_DATA" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    target = next((r for r in data if r.get('key') == 'build-artifacts-generic'), None)
    if target:
        print(json.dumps(target))
    else:
        print('{}')
except:
    print('{}')
")
fi

if [ "$REPO_INFO" != "{}" ]; then
    REPO_EXISTS="true"
    REPO_TYPE=$(echo "$REPO_INFO" | jq -r '.type // "unknown"')
    PACKAGE_TYPE=$(echo "$REPO_INFO" | jq -r '.packageType // "unknown"')
fi

# 2. Query Artifact Information
echo "Querying artifact storage..."
ARTIFACT_PATH="releases/v1.0/commons-lang3-3.14.0.jar"
ARTIFACT_URL="http://localhost:8082/artifactory/api/storage/build-artifacts-generic/$ARTIFACT_PATH"
ARTIFACT_EXISTS="false"
ARTIFACT_SIZE="0"
ARTIFACT_CREATED_BY="unknown"
ARTIFACT_CREATED_TIME="0"

ARTIFACT_JSON=$(curl -s -u admin:password "$ARTIFACT_URL")

# Check if artifact exists (storage API returns info if exists, or errors if not)
if echo "$ARTIFACT_JSON" | grep -q "\"downloadUri\""; then
    ARTIFACT_EXISTS="true"
    ARTIFACT_SIZE=$(echo "$ARTIFACT_JSON" | jq -r '.size // 0')
    ARTIFACT_CREATED_BY=$(echo "$ARTIFACT_JSON" | jq -r '.createdBy // "unknown"')
    # ISO8601 to timestamp
    CREATED_ISO=$(echo "$ARTIFACT_JSON" | jq -r '.created // empty')
    if [ -n "$CREATED_ISO" ]; then
        ARTIFACT_CREATED_TIME=$(date -d "$CREATED_ISO" +%s 2>/dev/null || echo "0")
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "repo_exists": $REPO_EXISTS,
    "repo_type": "$REPO_TYPE",
    "package_type": "$PACKAGE_TYPE",
    "artifact_exists": $ARTIFACT_EXISTS,
    "artifact_path": "$ARTIFACT_PATH",
    "artifact_size": $ARTIFACT_SIZE,
    "artifact_created_by": "$ARTIFACT_CREATED_BY",
    "artifact_created_time": $ARTIFACT_CREATED_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="