#!/bin/bash
set -euo pipefail
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if application (Firefox) was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Query Redmine Database for Project Configuration
# We use rails runner inside the container to get the exact state of the project objects
echo "Querying Redmine database..."

PROJECT_ID="orion-satellite"
TARGET_VERSION="v2.1-Beta"
TARGET_USER="sconnor"

RUBY_SCRIPT="
require 'json'
begin
  p = Project.find_by_identifier('$PROJECT_ID')
  if p.nil?
    puts JSON.generate({error: 'Project not found'})
  else
    # Find the version
    v = p.versions.find_by(name: '$TARGET_VERSION')
    
    # Find the user
    u = User.find_by_login('$TARGET_USER')
    
    # Check what is currently set on the project
    current_default_version = p.default_version
    current_default_assignee = p.default_assigned_to
    
    result = {
      project_found: true,
      
      # version status
      version_created: !v.nil?,
      version_id: v ? v.id : nil,
      version_status: v ? v.status : nil,
      version_created_on: v ? v.created_on.to_i : 0,
      
      # user status
      user_id: u ? u.id : nil,
      
      # project defaults configuration
      default_version_id: p.default_version_id,
      default_assignee_id: p.default_assigned_to_id,
      
      # Helpers for verification
      is_correct_version_set: (v && p.default_version_id == v.id),
      is_correct_assignee_set: (u && p.default_assigned_to_id == u.id)
    }
    puts JSON.generate(result)
  end
rescue => e
  puts JSON.generate({error: e.message})
end
"

# Save ruby script to temp file and run it
DB_RESULT_JSON=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "$RUBY_SCRIPT" | grep "^{") || echo "{}"

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_state": $DB_RESULT_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="