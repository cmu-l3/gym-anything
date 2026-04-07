#!/bin/bash
echo "=== Exporting import_issues_from_csv result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Fetch Issues from Redmine API
# We fetch all issues for the project to verify import success
PROJECT_ID="oakwood-facilities"
API_OUTPUT="/tmp/redmine_issues.json"

echo "Fetching issues from Redmine API..."
curl -s -u admin:Admin1234! \
  "$REDMINE_BASE_URL/projects/$PROJECT_ID/issues.json?status_id=*&limit=100" \
  > "$API_OUTPUT"

# 4. Create Result JSON
# We bundle the API response with timestamps and metadata
RESULT_JSON="/tmp/task_result.json"
TEMP_JSON=$(mktemp)

# Read fields safely
TOTAL_COUNT=$(jq '.total_count // 0' "$API_OUTPUT" 2>/dev/null || echo "0")
ISSUES_JSON=$(jq '.issues // []' "$API_OUTPUT" 2>/dev/null || echo "[]")

cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "project_identifier": "$PROJECT_ID",
  "total_issue_count": $TOTAL_COUNT,
  "issues": $ISSUES_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

mv "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
echo "Total issues found: $TOTAL_COUNT"
echo "=== Export complete ==="