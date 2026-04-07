#!/bin/bash
set -e
echo "=== Exporting configure_repo_automation result ==="

source /workspace/scripts/task_utils.sh

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# 3. Extract the actual configuration from Redmine using Rails runner
# We fetch the current settings AND the IDs for 'Closed' and 'Development' to compare against.
# We also check the updated_on timestamp of the settings to ensure anti-gaming.
echo "Querying Redmine settings..."

RUBY_SCRIPT="
require 'json'

# Get expected IDs
status_closed = IssueStatus.find_by(name: 'Closed')&.id
activity_dev = TimeEntryActivity.find_by(name: 'Development')&.id

# Get actual settings
result = {
  'keywords' => Setting.commit_fix_keywords,
  'status_id' => Setting.commit_fix_status_id,
  'done_ratio' => Setting.commit_fix_done_ratio,
  'logtime_enabled' => Setting.commit_logtime_enabled,
  'activity_id' => Setting.commit_logtime_activity_id,
  
  # Context for verification
  'expected_status_id' => status_closed,
  'expected_activity_id' => activity_dev,
  
  # Anti-gaming: Check if settings were updated recently
  'settings_updated_on' => Setting.where(name: 'commit_fix_keywords').pick(:updated_on)
}

puts result.to_json
"

# Execute inside container and save to temp file
docker exec redmine bundle exec rails runner "$RUBY_SCRIPT" > /tmp/redmine_settings_export.json 2>/dev/null || echo "{}" > /tmp/redmine_settings_export.json

# 4. Prepare result JSON
# We merge the shell-level data with the Rails data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "redmine_data": $(cat /tmp/redmine_settings_export.json)
}
EOF

# 5. Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="