#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_issue_relation task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

SEED_FILE="/tmp/redmine_seed_result.json"
TASK_DATA="/tmp/task_relation_data.json"

# Wait for Redmine to be ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Get admin API key
API_KEY=$(redmine_admin_api_key)
if [ -z "$API_KEY" ]; then
  echo "ERROR: Could not retrieve admin API key"
  exit 1
fi

# Get the first project from seed data
PROJECT_ID=$(jq -r '.projects[0].identifier' "$SEED_FILE" 2>/dev/null)
PROJECT_NUM_ID=$(jq -r '.projects[0].id' "$SEED_FILE" 2>/dev/null)

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
  echo "ERROR: No project found in seed data"
  exit 1
fi

# Get 'Task' tracker ID
TRACKER_ID=$(curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/trackers.json" | jq -r '.trackers[] | select(.name=="Task") | .id' 2>/dev/null | head -1)
# Fallback to first tracker if 'Task' not found
if [ -z "$TRACKER_ID" ] || [ "$TRACKER_ID" = "null" ]; then
  TRACKER_ID=1
fi

echo "Creating issues in project $PROJECT_ID..."

# Create Issue A: "Complete site grading and earthwork"
ISSUE_A_RESPONSE=$(curl -s -X POST \
  -H "X-Redmine-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"issue\": {
      \"project_id\": $PROJECT_NUM_ID,
      \"tracker_id\": $TRACKER_ID,
      \"subject\": \"Complete site grading and earthwork\",
      \"description\": \"All grading, excavation, and compaction work for the building pad must be completed and inspected before any foundation work begins. Includes rough grading, fine grading, soil compaction testing, and civil engineer sign-off.\",
      \"priority_id\": 2
    }
  }" \
  "$REDMINE_BASE_URL/issues.json")
ISSUE_A_ID=$(echo "$ISSUE_A_RESPONSE" | jq -r '.issue.id')

# Create Issue B: "Pour foundation concrete"
ISSUE_B_RESPONSE=$(curl -s -X POST \
  -H "X-Redmine-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"issue\": {
      \"project_id\": $PROJECT_NUM_ID,
      \"tracker_id\": $TRACKER_ID,
      \"subject\": \"Pour foundation concrete\",
      \"description\": \"Foundation concrete pour for Building A footings and grade beams. Requires completed and approved site grading, rebar inspection, and formwork verification. Concrete spec: 4000 PSI with fiber mesh.\",
      \"priority_id\": 2
    }
  }" \
  "$REDMINE_BASE_URL/issues.json")
ISSUE_B_ID=$(echo "$ISSUE_B_RESPONSE" | jq -r '.issue.id')

if [ -z "$ISSUE_A_ID" ] || [ "$ISSUE_A_ID" = "null" ] || [ -z "$ISSUE_B_ID" ] || [ "$ISSUE_B_ID" = "null" ]; then
  echo "ERROR: Failed to create required issues"
  exit 1
fi

echo "Created Issue A: #$ISSUE_A_ID"
echo "Created Issue B: #$ISSUE_B_ID"

# Save task data for export/verification scripts
cat > "$TASK_DATA" << EOF
{
  "project_identifier": "$PROJECT_ID",
  "issue_a_id": $ISSUE_A_ID,
  "issue_b_id": $ISSUE_B_ID,
  "api_key": "$API_KEY"
}
EOF
chmod 644 "$TASK_DATA"

# Launch Firefox and login, navigating to the project issues list
ISSUES_URL="$REDMINE_BASE_URL/projects/$PROJECT_ID/issues"
echo "Opening Firefox at: $ISSUES_URL"
ensure_redmine_logged_in "$ISSUES_URL"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Captured initial screenshot."

echo "=== Task setup complete ==="