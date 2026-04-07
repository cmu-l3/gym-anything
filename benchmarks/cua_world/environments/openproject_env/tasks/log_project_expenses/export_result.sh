#!/bin/bash
set -e
echo "=== Exporting log_project_expenses result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to query the Rails app to see if the data was entered correctly.
# The expected IDs are in /tmp/task_data.json (created during setup).

cat > /tmp/verify_costs_task.rb << RUBY
require 'json'
begin
  # Load expected data
  task_data = JSON.parse(File.read('/tmp/task_data.json'))
  project_id = task_data['project_id']
  wp_id = task_data['wp_id']
  expected_cost_type_id = task_data['cost_type_id']
  
  # 1. Check Project Modules
  project = Project.find_by(id: project_id)
  module_enabled = project ? project.enabled_module_names.include?('costs') : false
  
  # 2. Check Cost Entry
  # We look for the MOST RECENT cost entry on this work package
  entry = CostEntry.where(work_package_id: wp_id).order(created_at: :desc).first
  
  entry_data = nil
  if entry
    entry_data = {
      'id' => entry.id,
      'cost_type_id' => entry.cost_type_id,
      'units' => entry.units.to_f,
      'comments' => entry.comments,
      'created_at_unixtime' => entry.created_at.to_i,
      'user_id' => entry.user_id
    }
  end

  result = {
    'module_enabled' => module_enabled,
    'entry_found' => !entry.nil?,
    'entry_data' => entry_data,
    'expected_cost_type_id' => expected_cost_type_id,
    'project_found' => !project.nil?
  }
  
  puts "__GA_VERIFY__" + result.to_json

rescue => e
  puts "__GA_VERIFY__" + { error: e.message, backtrace: e.backtrace }.to_json
end
RUBY

# Run verification script and capture output
# We use a marker __GA_VERIFY__ to separate rails noise from our JSON
OUTPUT=$(op_rails "$(cat /tmp/verify_costs_task.rb)")

# Extract JSON from output
JSON_PAYLOAD=$(echo "$OUTPUT" | grep "__GA_VERIFY__" | sed 's/.*__GA_VERIFY__//')

# Save to result file
if [ -n "$JSON_PAYLOAD" ]; then
    echo "$JSON_PAYLOAD" > /tmp/task_result.json
else
    echo '{"error": "Failed to extract verification JSON from Rails output"}' > /tmp/task_result.json
fi

# Add timestamp info to the result (merging JSONs using jq if available, or python)
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
    data['task_start'] = $TASK_START
    data['task_end'] = $TASK_END
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(f'Error merging timestamps: {e}')
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="