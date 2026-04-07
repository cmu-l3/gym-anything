#!/bin/bash
# Export script for Configure Project Labor Rates task
# extracting the current hourly rates from the database.

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract data via Rails runner
# We output a JSON object with the current rate configuration for Alice and Bob
echo "Querying database for hourly rates..."
RUBY_SCRIPT=$(cat <<EOF
require 'json'

begin
  project = Project.find_by(identifier: 'devops-automation')
  alice = User.find_by(login: 'alice.johnson')
  bob = User.find_by(login: 'bob.smith')
  
  result = {
    timestamp: Time.now.to_i,
    project_found: !project.nil?,
    rates: {}
  }

  if project
    [alice, bob].each do |user|
      next unless user
      
      # Get the most recent valid rate
      rate = HourlyRate.where(project: project, user: user)
                       .order(valid_from: :desc)
                       .first
      
      if rate
        result[:rates][user.login] = {
          rate: rate.rate.to_f,
          valid_from: rate.valid_from.to_s,
          created_at: rate.created_at.to_i
        }
      else
        result[:rates][user.login] = nil
      end
    end
  end

  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message })
end
EOF
)

# Run the script inside the container and capture output
# We filter stdout to find the JSON line (ignoring Rails boot logs)
JSON_OUTPUT=$(op_rails "$RUBY_SCRIPT" | grep -o '^{.*}$')

if [ -z "$JSON_OUTPUT" ]; then
    echo "Error: Could not capture valid JSON from Rails runner"
    # Create a fallback failure JSON
    echo '{"error": "Failed to extract data", "rates": {}}' > /tmp/task_result.json
else
    echo "$JSON_OUTPUT" > /tmp/task_result.json
fi

# 3. Add task start time to the result file for the verifier to use
# We read the JSON, add the task_start_time, and write it back
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use python to merge the start time safely
python3 -c "
import json
import sys

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
    
    data['task_start_time'] = int($TASK_START)
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f'Error updating JSON: {e}')
"

echo "Result stored in /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="