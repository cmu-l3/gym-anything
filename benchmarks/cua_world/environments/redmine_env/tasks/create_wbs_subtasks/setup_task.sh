#!/bin/bash
echo "=== Setting up create_wbs_subtasks task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is reachable
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# ==============================================================================
# Create the "Facilities Renovation" project via API
# ==============================================================================
PROJECT_ID="facilities-renovation"
PROJECT_NAME="Facilities Renovation"
ADMIN_AUTH="admin:Admin1234!"

echo "Checking if project $PROJECT_ID exists..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_AUTH" \
  "$REDMINE_BASE_URL/projects/$PROJECT_ID.json")

if [ "$HTTP_CODE" == "200" ]; then
  echo "Project $PROJECT_ID already exists. Cleaning up specific issues..."
  # (Optional: delete existing issues if we wanted a truly clean slate, 
  # but for now we'll just append new ones. The verifier checks for NEW issues.)
else
  echo "Creating project $PROJECT_ID..."
  curl -s -X POST -u "$ADMIN_AUTH" \
    -H "Content-Type: application/json" \
    -d "{\"project\": {\"name\": \"$PROJECT_NAME\", \"identifier\": \"$PROJECT_ID\", \"enabled_module_names\": [\"issue_tracking\"]}}" \
    "$REDMINE_BASE_URL/projects.json"
fi

# Enable Subtasks in Settings if not already (Cross-check via API or assume default)
# Default Redmine usually allows subtasks.

# Record initial issue count
INITIAL_COUNT=$(curl -s -u "$ADMIN_AUTH" "$REDMINE_BASE_URL/issues.json?project_id=$PROJECT_ID&limit=1" | jq '.total_count')
echo "${INITIAL_COUNT:-0}" > /tmp/initial_issue_count.txt
echo "Initial issue count: ${INITIAL_COUNT:-0}"

# ==============================================================================
# Launch Firefox and Login
# ==============================================================================
TARGET_URL="$REDMINE_BASE_URL/projects/$PROJECT_ID/issues"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

# Maximize and Focus
focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
log "Task start screenshot: /tmp/task_initial.png"

echo "=== Task setup complete ==="