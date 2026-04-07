#!/bin/bash
# Export script for create_custom_enumerations task
# Queries OpenProject DB via Rails runner to verify configuration changes

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Read initial states
INIT_PRIORITY_COUNT=$(cat /tmp/initial_priority_count.txt 2>/dev/null || echo "0")
INIT_ACTIVITY_COUNT=$(cat /tmp/initial_activity_count.txt 2>/dev/null || echo "0")
INIT_WP_PRIORITY=$(cat /tmp/initial_wp_priority.txt 2>/dev/null || echo "")

# Define the verification Ruby script to run inside the container
# This script gathers all necessary data points in one go
cat > /tmp/verify_script.rb << 'RUBY_EOF'
require 'json'

begin
  results = {
    priorities: {},
    activities: {},
    work_package: {},
    counts: {}
  }

  # Check specific priorities
  ["Critical - Safety", "Regulatory Deadline"].each do |p_name|
    p = IssuePriority.find_by(name: p_name)
    results[:priorities][p_name] = {
      exists: !p.nil?,
      active: p ? p.active? : false,
      is_default: p ? p.is_default? : false
    }
  end

  # Check specific activity
  a_name = "Security Audit"
  a = TimeEntryActivity.find_by(name: a_name)
  results[:activities][a_name] = {
    exists: !a.nil?,
    active: a ? a.active? : false
  }

  # Check Work Package
  wp = WorkPackage.find_by(subject: "Fix broken checkout on mobile Safari")
  results[:work_package] = {
    found: !wp.nil?,
    priority_name: (wp && wp.priority) ? wp.priority.name : nil
  }

  # Check total counts
  results[:counts] = {
    priorities: IssuePriority.count,
    activities: TimeEntryActivity.count
  }

  puts JSON.generate(results)
rescue => e
  puts JSON.generate({ error: e.message, backtrace: e.backtrace })
end
RUBY_EOF

# Copy script to container
docker cp /tmp/verify_script.rb openproject:/tmp/verify_script.rb

# Run the script inside container
echo "Running verification script inside OpenProject container..."
docker exec openproject bash -lc "cd /app && bin/rails runner -e production /tmp/verify_script.rb" > /tmp/rails_output.json 2>/dev/null

# Validate JSON output
if ! jq . /tmp/rails_output.json >/dev/null 2>&1; then
    echo "Error: Rails runner did not output valid JSON"
    echo "{}" > /tmp/rails_output.json
fi

# Create final result JSON combining everything
# We use Python to merge the Rails JSON with our shell variables safely
python3 -c "
import json
import os

try:
    with open('/tmp/rails_output.json') as f:
        rails_data = json.load(f)
except:
    rails_data = {}

result = {
    'task_start': int(os.environ.get('TASK_START', 0)),
    'task_end': int(os.environ.get('TASK_END', 0)),
    'initial_state': {
        'priority_count': int(os.environ.get('INIT_PRIORITY_COUNT', 0)),
        'activity_count': int(os.environ.get('INIT_ACTIVITY_COUNT', 0)),
        'wp_priority': os.environ.get('INIT_WP_PRIORITY', '')
    },
    'rails_data': rails_data,
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Cleanup temp files
rm -f /tmp/verify_script.rb /tmp/rails_output.json

# Set permissions so the host can read it (if needed)
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="