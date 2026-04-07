#!/bin/bash
echo "=== Exporting create_wbs_subtasks result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_issue_count.txt 2>/dev/null || echo "0")
PROJECT_ID="facilities-renovation"
ADMIN_AUTH="admin:Admin1234!"

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# Fetch Issue Data via Redmine API
# ==============================================================================
echo "Fetching issues from Redmine API..."

# We fetch all issues for the project, including children status
# Using a high limit to ensure we get them all
API_RESPONSE=$(curl -s -u "$ADMIN_AUTH" \
  "$REDMINE_BASE_URL/issues.json?project_id=$PROJECT_ID&status_id=*&limit=100")

# Save raw response for debugging
echo "$API_RESPONSE" > /tmp/redmine_issues_raw.json

# Check current count
FINAL_COUNT=$(echo "$API_RESPONSE" | jq '.total_count')
COUNT_DELTA=$((FINAL_COUNT - INITIAL_COUNT))

# Create a clean JSON result file
# We extract the issues list to be parsed by Python
cat > /tmp/task_result_temp.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "count_delta": $COUNT_DELTA,
    "project_id": "$PROJECT_ID",
    "issues_data": $API_RESPONSE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="