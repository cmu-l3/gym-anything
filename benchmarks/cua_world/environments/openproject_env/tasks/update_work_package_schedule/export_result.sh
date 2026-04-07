#!/bin/bash
# Export script for update_work_package_schedule
# Queries the OpenProject database via Rails runner to get the final state of the work package.
# Also captures a final screenshot.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting update_work_package_schedule result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Work Package State using Rails Runner
# We extract the specific fields the agent was supposed to change.
# We also get 'updated_at' to verify the change happened during the task.
echo "Querying work package status..."
RUBY_SCRIPT="
require 'json'
begin
  wp = WorkPackage.joins(:project)
        .where(projects: {identifier: 'ecommerce-platform'})
        .where('work_packages.subject LIKE ?', '%product recommendation engine%')
        .first

  result = {
    found: !wp.nil?,
    subject: wp&.subject,
    start_date: wp&.start_date&.to_s,       # Standard ISO format YYYY-MM-DD
    due_date: wp&.due_date&.to_s,           # Standard ISO format YYYY-MM-DD
    estimated_hours: wp&.estimated_hours,   # Float
    done_ratio: wp&.done_ratio,             # Integer (0-100)
    updated_at: wp&.updated_at&.to_i        # Unix timestamp
  }
  
  puts 'JSON_START'
  puts result.to_json
  puts 'JSON_END'
rescue => e
  puts 'JSON_START'
  puts({ error: e.message }.to_json)
  puts 'JSON_END'
end
"

# Run the script inside the container and capture output
# Use a temp file to avoid pipe issues with docker exec
docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_SCRIPT\"" > /tmp/rails_output.txt 2>&1 || true

# Extract JSON from the output (OpenProject logs might add noise)
cat /tmp/rails_output.txt | sed -n '/JSON_START/,/JSON_END/p' | sed '1d;$d' > /tmp/task_result.json

# 3. Add task timing info to the result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use python to merge the timing info into the JSON safely
python3 -c "
import json
import os

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {'found': False, 'error': 'Failed to parse Rails output'}

data['task_start_timestamp'] = $TASK_START
data['task_end_timestamp'] = $TASK_END

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 4. Set permissions so the host can read it via copy_from_env
chmod 666 /tmp/task_result.json

echo "Export complete. Result content:"
cat /tmp/task_result.json
echo "=== Export script finished ==="