#!/bin/bash
echo "=== Exporting Rebalance Team Workload Results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
take_screenshot /tmp/task_final.png

# Retrieve current state of the issues using Rails runner
# (More reliable than curl here since we need full history/notes)
cat > /tmp/export_state.rb << 'RBEOF'
project = Project.find_by(identifier: 'payment-gateway-api')
issues = project.issues.includes(:assigned_to, :priority, :journals).all

data = issues.map do |i|
  {
    id: i.id,
    subject: i.subject,
    assigned_to_id: i.assigned_to_id,
    assigned_to_login: i.assigned_to ? i.assigned_to.login : nil,
    priority_name: i.priority.name,
    updated_on: i.updated_on.to_i,
    notes: i.journals.map(&:notes).reject(&:blank?)
  }
end

puts JSON.generate(data)
RBEOF

docker cp /tmp/export_state.rb redmine:/tmp/export_state.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/export_state.rb > /tmp/final_issue_state.json

# Clean up JSON output (sometimes rails runner outputs extra logs)
# Extract just the array line
grep "^\\[" /tmp/final_issue_state.json > /tmp/clean_final_state.json || cp /tmp/final_issue_state.json /tmp/clean_final_state.json

# Prepare result package
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "initial_state": $(cat /tmp/initial_scenario_state.json 2>/dev/null || echo "{}"),
  "final_issues": $(cat /tmp/clean_final_state.json 2>/dev/null || echo "[]"),
  "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"