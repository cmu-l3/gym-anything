#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Run verification script inside OpenProject container
# We extract the query attributes directly from the database
echo "Querying OpenProject database for saved view..."

# Ruby script to inspect the query
RUBY_SCRIPT=$(cat <<EOF
require 'json'

# Find the query by name. We look for the most recently created one.
query = Query.where(name: 'PMO Portfolio').order(created_at: :desc).first

result = {
  found: false,
  is_public: false,
  columns: [],
  sort_criteria: [],
  created_at: 0
}

if query
  result[:found] = true
  result[:is_public] = query.is_public
  
  # Normalize column names to strings
  result[:columns] = query.column_names.map(&:to_s)
  
  # Sort criteria is usually an array of arrays [['field', 'asc/desc']]
  result[:sort_criteria] = query.sort_criteria
  
  result[:created_at] = query.created_at.to_i
end

puts JSON.generate(result)
EOF
)

# Execute the Ruby script and capture output
# We use the op_rails helper but need to capture stdout
JSON_OUTPUT=$(docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_SCRIPT\" 2>/dev/null")

# Handle case where rails runner fails or returns garbage
if [ -z "$JSON_OUTPUT" ]; then
    JSON_OUTPUT='{"found": false, "error": "Rails runner returned empty response"}'
fi

# 3. Save result to file
echo "$JSON_OUTPUT" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

# 4. Check if the app was running (Browser)
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Add app_running status to the JSON (using jq or python to merge)
# Simple python merge to avoid jq dependency issues if not installed
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
    data['app_was_running'] = $APP_RUNNING
    # Add timestamp from setup to the result for comparison
    with open('/tmp/task_start_time.txt', 'r') as f:
        data['task_start_time'] = int(f.read().strip())
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(f'Error updating JSON: {e}')
"

echo "Exported JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="