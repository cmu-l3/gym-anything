#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_project_release_defaults task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Wait for Redmine
wait_for_http "$REDMINE_BASE_URL" 120

# 2. Get Admin API Key
API_KEY=$(redmine_admin_api_key)
if [ -z "$API_KEY" ]; then
  echo "ERROR: Could not retrieve admin API key"
  exit 1
fi

# 3. Create Project "Orion Satellite Interface"
PROJECT_NAME="Orion Satellite Interface"
PROJECT_ID="orion-satellite"

# Check if project exists, delete if so (cleanup from previous runs)
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "Project.find_by_identifier('$PROJECT_ID')&.destroy" 2>/dev/null || true

echo "Creating project: $PROJECT_NAME..."
curl -s -X POST "$REDMINE_BASE_URL/projects.json" \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: $API_KEY" \
  -d "{
    \"project\": {
      \"name\": \"$PROJECT_NAME\",
      \"identifier\": \"$PROJECT_ID\",
      \"description\": \"Satellite telemetry and control interface system.\",
      \"is_public\": true
    }
  }" > /dev/null

# 4. Create User "Sarah Connor"
USER_LOGIN="sconnor"
USER_FIRST="Sarah"
USER_LAST="Connor"
USER_PASS="Terminator2!"

echo "Creating user: $USER_LOGIN..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "
    u = User.find_by_login('$USER_LOGIN')
    if u.nil?
      u = User.new(
        login: '$USER_LOGIN',
        firstname: '$USER_FIRST',
        lastname: '$USER_LAST',
        mail: 'sconnor@cyberdyne.invalid',
        language: 'en'
      )
      u.password = '$USER_PASS'
      u.password_confirmation = '$USER_PASS'
      u.save!
    end
    puts \"User ID: #{u.id}\"
"

# 5. Add Sarah to Project as Manager
echo "Adding user to project..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "
    u = User.find_by_login('$USER_LOGIN')
    p = Project.find_by_identifier('$PROJECT_ID')
    r = Role.find_by_name('Manager')
    if p && u && r
      m = Member.new(user: u, project: p)
      m.roles = [r]
      m.save!
      puts \"Added #{u.login} to #{p.name}\"
    end
"

# 6. Login and Navigate to Project Settings
TARGET_URL="$REDMINE_BASE_URL/projects/$PROJECT_ID/settings"
echo "Logging in and navigating to: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
log "Task start screenshot: /tmp/task_initial.png"

echo "=== Setup Complete ==="