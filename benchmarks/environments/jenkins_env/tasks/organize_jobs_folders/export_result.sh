#!/bin/bash
set -e
echo "=== Exporting organize_jobs_folders results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/organize_jobs_folders_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# Helper: safely query API and return empty object on failure
safe_api() {
    local endpoint="$1"
    local result
    result=$(jenkins_api "$endpoint" 2>/dev/null)
    # Check if result is valid JSON
    if echo "$result" | jq -e . >/dev/null 2>&1; then
        echo "$result"
    else
        echo "{}"
    fi
}

# 1. Query Top-Level items (to check folders and detect misplaced jobs)
TOP_LEVEL=$(safe_api "api/json")

# 2. Query 'platform-team' folder
PLATFORM_FOLDER=$(safe_api "job/platform-team/api/json")
PLATFORM_FOLDER_CONFIG=""
if [ "$(echo "$PLATFORM_FOLDER" | jq 'has("_class")')" = "true" ]; then
    PLATFORM_FOLDER_CONFIG=$(jenkins_api "job/platform-team/config.xml" 2>/dev/null || echo "")
fi

# 3. Query 'api-service-build' job INSIDE platform-team
API_JOB=$(safe_api "job/platform-team/job/api-service-build/api/json")
API_JOB_CONFIG=""
if [ "$(echo "$API_JOB" | jq 'has("_class")')" = "true" ]; then
    API_JOB_CONFIG=$(jenkins_api "job/platform-team/job/api-service-build/config.xml" 2>/dev/null || echo "")
fi

# 4. Query 'frontend-team' folder
FRONTEND_FOLDER=$(safe_api "job/frontend-team/api/json")
FRONTEND_FOLDER_CONFIG=""
if [ "$(echo "$FRONTEND_FOLDER" | jq 'has("_class")')" = "true" ]; then
    FRONTEND_FOLDER_CONFIG=$(jenkins_api "job/frontend-team/config.xml" 2>/dev/null || echo "")
fi

# 5. Query 'webapp-build' job INSIDE frontend-team
WEBAPP_JOB=$(safe_api "job/frontend-team/job/webapp-build/api/json")
WEBAPP_JOB_CONFIG=""
if [ "$(echo "$WEBAPP_JOB" | jq 'has("_class")')" = "true" ]; then
    WEBAPP_JOB_CONFIG=$(jenkins_api "job/frontend-team/job/webapp-build/config.xml" 2>/dev/null || echo "")
fi

# 6. Check for misplaced jobs at root (Anti-gaming/Error detection)
API_TOP=$(safe_api "job/api-service-build/api/json")
WEBAPP_TOP=$(safe_api "job/webapp-build/api/json")

# Escape XML content for JSON inclusion
escape_xml() {
    echo "$1" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))"
}

# Build the Result JSON
# We use python to safely construct JSON to avoid bash quoting hell
python3 -c "
import json
import sys

data = {
    'task_start_time': $TASK_START,
    'initial_item_count': $INITIAL_COUNT,
    'top_level': json.loads('''$TOP_LEVEL'''),
    'platform_folder': {
        'metadata': json.loads('''$PLATFORM_FOLDER'''),
        'config_xml': $(escape_xml "$PLATFORM_FOLDER_CONFIG")
    },
    'api_service_build': {
        'metadata': json.loads('''$API_JOB'''),
        'config_xml': $(escape_xml "$API_JOB_CONFIG")
    },
    'frontend_folder': {
        'metadata': json.loads('''$FRONTEND_FOLDER'''),
        'config_xml': $(escape_xml "$FRONTEND_FOLDER_CONFIG")
    },
    'webapp_build': {
        'metadata': json.loads('''$WEBAPP_JOB'''),
        'config_xml': $(escape_xml "$WEBAPP_JOB_CONFIG")
    },
    'misplaced': {
        'api_service_build_at_root': json.loads('''$API_TOP'''),
        'webapp_build_at_root': json.loads('''$WEBAPP_TOP''')
    }
}
print(json.dumps(data, indent=2))
" > "$RESULT_FILE"

# Take final screenshot
take_screenshot /tmp/task_final_state.png

echo "Results saved to $RESULT_FILE"
echo "=== Export complete ==="