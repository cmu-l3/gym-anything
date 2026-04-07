#!/bin/bash
# Export script for escalate_project_health_status task

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Capture final screenshot (visual evidence)
take_screenshot /tmp/task_final.png

# 2. Query the Project Status from the database via Rails
# We extract the status code/name, explanation, and timestamp
echo "Querying project status..."
RUBY_SCRIPT="
  require 'json';
  p = Project.find_by(identifier: 'mobile-banking-app');
  result = { found: false };
  
  if p && p.status
    s = p.status;
    result = {
      found: true,
      status_name: s.respond_to?(:name) ? s.name : s.code.to_s,
      # Different OP versions store the enum/code differently, trying common methods
      status_code: s.respond_to?(:code) ? s.code : nil,
      explanation: s.explanation,
      updated_at: s.updated_at.to_i,
      created_at: s.created_at.to_i
    };
  end
  
  puts JSON.generate(result);
"

# Run the ruby script inside the container and capture output
# We filter the output to find the JSON line (Rails runner can be noisy)
JSON_OUTPUT=$(op_rails "$RUBY_SCRIPT" | grep -o '^{.*}')

# 3. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Create the final result JSON file
# Use a temporary file first to avoid permission issues
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)

if [ -n "$JSON_OUTPUT" ]; then
    echo "$JSON_OUTPUT" > "$TEMP_JSON"
else
    echo '{"found": false, "error": "Failed to retrieve status"}' > "$TEMP_JSON"
fi

# Merge timing info using jq (installed in env) or simple python append
# Since jq might not be in the minimal environment hooks context (though it is in the env), 
# we'll use Python for robustness.
python3 -c "
import json, sys
try:
    with open('$TEMP_JSON', 'r') as f:
        data = json.load(f)
    data['task_start'] = $TASK_START
    data['task_end'] = $TASK_END
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(f'Error processing JSON: {e}')
"

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json