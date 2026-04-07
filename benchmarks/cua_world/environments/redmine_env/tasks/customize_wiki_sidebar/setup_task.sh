#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: customize_wiki_sidebar ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Redmine is running
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# 2. Check if project exists, if not create it via API
# We do this to ensure a clean starting state for the wiki
API_KEY=$(redmine_admin_api_key)
PROJECT_ID=$(redmine_project_id "engineering-handbook")

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    echo "Creating 'Engineering Handbook' project..."
    curl -s -X POST "$REDMINE_BASE_URL/projects.json" \
      -H "Content-Type: application/json" \
      -H "X-Redmine-API-Key: $API_KEY" \
      -d '{
        "project": {
          "name": "Engineering Handbook",
          "identifier": "engineering-handbook",
          "enabled_module_names": ["wiki", "issue_tracking"]
        }
      }'
    
    # Wait for project to be ready
    sleep 2
    PROJECT_ID=$(redmine_project_id "engineering-handbook")
fi

echo "Project ID: $PROJECT_ID"

# 3. Initialize Wiki by creating the Start page
# (Wiki module needs a start page to be fully active/visible)
echo "Initializing Wiki Start page..."
curl -s -X PUT "$REDMINE_BASE_URL/projects/engineering-handbook/wiki/Wiki.json" \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: $API_KEY" \
  -d '{
    "wiki_page": {
      "text": "h1. Engineering Handbook\n\nWelcome to the engineering team knowledge base.",
      "comments": "Initial setup"
    }
  }'

# 4. Ensure any previous Sidebar or target pages are removed (idempotency)
# We use docker exec to run a cleanup script inside the container
docker exec redmine bundle exec rails runner "
  p = Project.find_by(identifier: 'engineering-handbook')
  if p && p.wiki
    ['Sidebar', 'Coding_Standards', 'Deployment_Procedures', 'Onboarding_Checklist'].each do |t|
      page = p.wiki.find_page(t)
      page.destroy if page
    end
  end
" 2>/dev/null || true

# 5. Log in and navigate to the Project Wiki
TARGET_URL="$REDMINE_BASE_URL/projects/engineering-handbook/wiki"
echo "Navigating to $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine"
  exit 1
fi

# 6. Capture initial state
focus_firefox
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="