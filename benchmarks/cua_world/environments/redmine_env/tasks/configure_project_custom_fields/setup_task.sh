#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_project_custom_fields task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
wait_for_http "$REDMINE_BASE_URL" 120

# Get Admin API Key
API_KEY=$(redmine_admin_api_key)
if [ -z "$API_KEY" ]; then
  echo "ERROR: Could not retrieve admin API key"
  exit 1
fi

# 1. Clean up any existing custom fields with these names to ensure clean state
# We use a ruby script inside the container for easier ActiveRecord interaction
cat > /tmp/clean_fields.rb <<RB
begin
  fields = CustomField.where(name: ['Regulatory Compliance', 'Budget Code', 'Portfolio Phase'])
  fields.destroy_all
  puts "Cleaned up #{fields.count} existing custom fields."
rescue => e
  puts "Error cleaning fields: #{e.message}"
end
RB
docker cp /tmp/clean_fields.rb redmine:/tmp/clean_fields.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/clean_fields.rb -e production

# 2. Ensure target project exists
PROJECT_IDENTIFIER="mobile-banking-upgrade"
PROJECT_NAME="Mobile Banking Upgrade"

# Check if project exists
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/projects/$PROJECT_IDENTIFIER.json")

if [ "$HTTP_CODE" != "200" ]; then
  echo "Creating project: $PROJECT_NAME..."
  curl -s -X POST -H "Content-Type: application/json" -H "X-Redmine-API-Key: $API_KEY" \
    -d "{\"project\": {\"name\": \"$PROJECT_NAME\", \"identifier\": \"$PROJECT_IDENTIFIER\", \"description\": \"Core banking system upgrade for mobile channels.\"}}" \
    "$REDMINE_BASE_URL/projects.json"
else
  echo "Project $PROJECT_NAME already exists."
fi

# 3. Open Firefox logged in as Admin, on the Custom Fields page
# We start at the Administration page to be helpful, but not deep linking to 'new'
TARGET_URL="$REDMINE_BASE_URL/admin"

log "Logging in and navigating to $TARGET_URL"
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to login"
  exit 1
fi

# 4. Capture initial state
take_screenshot /tmp/task_initial.png

# Record initial count of custom fields for anti-gaming
INITIAL_CF_COUNT=$(curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/custom_fields.json" | jq '.custom_fields | length')
echo "$INITIAL_CF_COUNT" > /tmp/initial_cf_count.txt

echo "=== Setup complete ==="