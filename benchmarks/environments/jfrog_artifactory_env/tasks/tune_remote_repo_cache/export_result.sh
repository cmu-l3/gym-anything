#!/bin/bash
# Export script for tune_remote_repo_cache task
echo "=== Exporting tune_remote_repo_cache results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Artifactory is accessible
ARTIFACTORY_ACCESSIBLE="false"
if curl -s -o /dev/null -m 5 "${ARTIFACTORY_URL}/artifactory/api/system/ping"; then
    ARTIFACTORY_ACCESSIBLE="true"
fi

# Fetch the final configuration of the repository
REPO_KEY="maven-central-remote"
REPO_CONFIG_JSON="{}"
RETRIEVAL_CACHE_SECS="-1"
REPO_EXISTS="false"

if [ "$ARTIFACTORY_ACCESSIBLE" == "true" ]; then
    echo "Fetching final repository configuration..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/repositories/${REPO_KEY}")
    
    if [ "$HTTP_CODE" == "200" ]; then
        REPO_EXISTS="true"
        REPO_CONFIG_JSON=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/repositories/${REPO_KEY}")
        
        # Extract the specific value we care about using python
        RETRIEVAL_CACHE_SECS=$(echo "$REPO_CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('retrievalCachePeriodSecs', -1))" 2>/dev/null || echo "-1")
    else
        echo "Repository $REPO_KEY not found (HTTP $HTTP_CODE)"
    fi
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "artifactory_accessible": $ARTIFACTORY_ACCESSIBLE,
    "repo_exists": $REPO_EXISTS,
    "repo_key": "$REPO_KEY",
    "retrieval_cache_period_secs": $RETRIEVAL_CACHE_SECS,
    "full_config": $REPO_CONFIG_JSON,
    "initial_val": $(cat /tmp/initial_cache_value.txt 2>/dev/null || echo "-1")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="