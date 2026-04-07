#!/bin/bash
echo "=== Exporting setup_secure_project_workspace result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. API Verification Data Collection
API_KEY=$(redmine_admin_api_key)
PROJECT_IDENTIFIER="hr-cases"
API_RESULT_FILE="/tmp/api_project_data.json"
MEMBERSHIP_RESULT_FILE="/tmp/api_membership_data.json"

# Fetch project details (including modules and trackers)
if [ -n "$API_KEY" ]; then
    echo "Fetching project details via API..."
    curl -s -H "X-Redmine-API-Key: $API_KEY" \
        "$REDMINE_BASE_URL/projects/$PROJECT_IDENTIFIER.json?include=trackers,enabled_modules" \
        > "$API_RESULT_FILE" || echo "{}" > "$API_RESULT_FILE"

    echo "Fetching project memberships via API..."
    curl -s -H "X-Redmine-API-Key: $API_KEY" \
        "$REDMINE_BASE_URL/projects/$PROJECT_IDENTIFIER/memberships.json?limit=100" \
        > "$MEMBERSHIP_RESULT_FILE" || echo "{}" > "$MEMBERSHIP_RESULT_FILE"
else
    echo "ERROR: Admin API key not found."
    echo "{}" > "$API_RESULT_FILE"
    echo "{}" > "$MEMBERSHIP_RESULT_FILE"
fi

# 3. Read the expected manager login
EXPECTED_MANAGER_LOGIN=$(cat /home/ga/hr_manager_login.txt 2>/dev/null || echo "")

# 4. Construct final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg manager "$EXPECTED_MANAGER_LOGIN" \
    --slurpfile project "$API_RESULT_FILE" \
    --slurpfile memberships "$MEMBERSHIP_RESULT_FILE" \
    '{
        task_start: $start,
        task_end: $end,
        target_manager_login: $manager,
        project_data: ($project[0] // {}),
        membership_data: ($memberships[0] // {}),
        screenshot_path: "/tmp/task_final.png"
    }' > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"