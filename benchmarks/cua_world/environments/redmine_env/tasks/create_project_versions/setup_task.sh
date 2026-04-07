#!/bin/bash
set -euo pipefail
echo "=== Setting up create_project_versions task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
wait_for_http "$REDMINE_BASE_URL" 60

# --- DATA PREPARATION ---
# Use jq to extract project/api key from the seed result file
SEED="/tmp/redmine_seed_result.json"
if [ ! -f "$SEED" ]; then
  echo "ERROR: Seed result not found at $SEED"
  exit 1
fi

API_KEY=$(jq -r '.admin_api_key' "$SEED")
# Select the first project
PROJECT_ID=$(jq -r '.projects[0].identifier' "$SEED")
PROJECT_NAME=$(jq -r '.projects[0].name' "$SEED")

# Ensure the "issue_tracking" module is enabled (required for Versions/Roadmap)
# We send a PUT to update the project modules
echo "Enabling issue_tracking module for project $PROJECT_ID..."
curl -s -X PUT \
  -H "X-Redmine-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"project":{"enabled_module_names":["issue_tracking","time_tracking","news","documents","files","wiki","repository","boards","calendar","gantt"]}}' \
  "$REDMINE_BASE_URL/projects/$PROJECT_ID.json" > /dev/null || true

# Fetch 2 issues from this project to use for assignment
ISSUES_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" \
  "$REDMINE_BASE_URL/issues.json?project_id=$PROJECT_ID&limit=5&sort=id")

ISSUE1_ID=$(echo "$ISSUES_JSON" | jq -r '.issues[0].id // empty')
ISSUE2_ID=$(echo "$ISSUES_JSON" | jq -r '.issues[1].id // empty')
ISSUE1_SUBJECT=$(echo "$ISSUES_JSON" | jq -r '.issues[0].subject // empty')
ISSUE2_SUBJECT=$(echo "$ISSUES_JSON" | jq -r '.issues[1].subject // empty')

if [ -z "$ISSUE1_ID" ] || [ -z "$ISSUE2_ID" ]; then
  echo "ERROR: Project $PROJECT_ID does not have enough issues for this task."
  exit 1
fi

# Store critical metadata for export/verification later
cat > /tmp/task_metadata_internal.json << EOF
{
  "project_identifier": "$PROJECT_ID",
  "project_name": "$PROJECT_NAME",
  "issue1_id": $ISSUE1_ID,
  "issue2_id": $ISSUE2_ID,
  "api_key": "$API_KEY"
}
EOF
chmod 644 /tmp/task_metadata_internal.json

# Record initial version count for anti-gaming (comparing before/after)
INITIAL_VERSIONS=$(curl -s -H "X-Redmine-API-Key: $API_KEY" \
  "$REDMINE_BASE_URL/projects/$PROJECT_ID/versions.json" | jq '.versions | length' 2>/dev/null || echo "0")
echo "$INITIAL_VERSIONS" > /tmp/initial_version_count.txt

# Create the Task Brief for the agent
cat > /home/ga/task_brief.txt << EOF
=== Construction Renovation Project - Milestone Setup ===

Project Name: $PROJECT_NAME
Project Identifier: $PROJECT_ID
Redmine URL: $REDMINE_BASE_URL

Issues to assign to Phase 1:
  - Issue #$ISSUE1_ID: $ISSUE1_SUBJECT
  - Issue #$ISSUE2_ID: $ISSUE2_SUBJECT

Login credentials: admin / Admin1234!
EOF
chown ga:ga /home/ga/task_brief.txt
chmod 644 /home/ga/task_brief.txt

# --- UI SETUP ---
# Launch Firefox logged in as admin, on the project overview page
TARGET_URL="$REDMINE_BASE_URL/projects/$PROJECT_ID"
ensure_redmine_logged_in "$TARGET_URL"

# Capture initial state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Project: $PROJECT_ID"
echo "Issues: #$ISSUE1_ID, #$ISSUE2_ID"