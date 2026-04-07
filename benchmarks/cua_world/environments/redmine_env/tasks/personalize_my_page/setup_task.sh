#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up 'Personalize My Page' task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

wait_for_http "$REDMINE_BASE_URL" 120

# 1. Reset Admin User Preferences to a known state
# We use rails runner to programmatically reset the layout to default items
# This ensures the agent isn't starting with the task already done
echo "Resetting admin 'My Page' layout..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine bundle exec rails runner -e production "
  u = User.find_by_login('admin')
  if u
    # Reset to default 'Issues assigned to me' and 'Reported issues'
    u.pref[:my_page_layout] = {'top' => ['issuesassignedtome'], 'left' => ['reportedissues'], 'right' => []} 
    u.pref.save!
    puts 'Admin preferences reset.'
  end
"

# 2. Seed some data so the blocks aren't empty (Visual confirmation for agent)
# Create a news item so 'Latest news' looks populated
echo "Seeding a News item..."
API_KEY=$(redmine_admin_api_key)
# Get a project ID - 'ecotourism-app-mvp' is from the seed script
PROJECT_ID=$(redmine_project_id "ecotourism-app-mvp")
if [ -z "$PROJECT_ID" ]; then
  # Fallback to first project
  PROJECT_ID="1"
fi

if [ -n "$API_KEY" ]; then
  # Create News
  curl -s -X POST -H "Content-Type: application/json" \
       -H "X-Redmine-API-Key: $API_KEY" \
       -d '{"news": {"title": "Q3 Strategic Review", "summary": "Mandatory attendance", "description": "The review will cover Q3 goals."}}' \
       "$REDMINE_BASE_URL/projects/$PROJECT_ID/news.json" > /dev/null || true
  
  # Log some time so 'Spent time' block isn't empty
  curl -s -X POST -H "Content-Type: application/json" \
       -H "X-Redmine-API-Key: $API_KEY" \
       -d '{"time_entry": {"issue_id": 1, "hours": 2.5, "activity_id": 9, "comments": "Task prep"}}' \
       "$REDMINE_BASE_URL/time_entries.json" > /dev/null || true
fi

# 3. Log in and navigate to My Page
ensure_redmine_logged_in "$REDMINE_BASE_URL/my/page"

# 4. Save initial screenshot
take_screenshot "/tmp/task_initial_state.png"

echo "=== Task setup complete ==="