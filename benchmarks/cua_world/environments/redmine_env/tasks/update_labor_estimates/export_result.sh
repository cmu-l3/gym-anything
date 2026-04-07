#!/bin/bash
set -euo pipefail

echo "=== Exporting update_labor_estimates results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the database to get the final state of issues
CHECK_SCRIPT="/tmp/check_estimates.rb"
JSON_OUTPUT="/tmp/db_result.json"

cat > "$CHECK_SCRIPT" << 'RUBY'
require 'json'

project = Project.find_by(identifier: 'office-park-1')
results = []

if project
  project.issues.each do |issue|
    results << {
      id: issue.id,
      subject: issue.subject,
      priority: issue.priority.name,
      status_name: issue.status.name,
      is_closed: issue.status.is_closed?,
      estimated_hours: issue.estimated_hours.to_f,
      updated_on: issue.updated_on.to_i
    }
  end
end

puts results.to_json
RUBY

# Execute check script
docker cp "$CHECK_SCRIPT" redmine:/tmp/check_estimates.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/check_estimates.rb > "$JSON_OUTPUT"

# 3. Create the final result JSON including metadata
# We embed the DB result content into the main result JSON
DB_CONTENT=$(cat "$JSON_OUTPUT")
# Clean up if the ruby script output has extra lines (take the last line which should be the JSON array)
DB_CONTENT=$(tail -n 1 "$JSON_OUTPUT")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_issues": $DB_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="