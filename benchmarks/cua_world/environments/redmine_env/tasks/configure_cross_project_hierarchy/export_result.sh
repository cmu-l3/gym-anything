#!/bin/bash
echo "=== Exporting Configure Cross-Project Hierarchy results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Redmine database/rails for the final state
# We need to check:
# - The global setting value
# - The parent_id of the child issue
cat > /tmp/check_result.rb << 'RB'
begin
  child = Issue.find_by(subject: 'Cryogenic Fuel Pump Design')
  parent = Issue.find_by(subject: 'Next-Gen Thruster Initiative')
  
  result = {
    setting_value: Setting.cross_project_subtasks,
    child_issue_id: child ? child.id : nil,
    child_parent_id: child ? child.parent_id : nil,
    parent_issue_id: parent ? parent.id : nil,
    child_project_id: child ? child.project.identifier : nil,
    parent_project_id: parent ? parent.project.identifier : nil
  }
  
  puts result.to_json
rescue => e
  puts({ error: e.message }.to_json)
end
RB

echo "Querying final state..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" \
  redmine bundle exec rails runner /tmp/check_result.rb > /tmp/rails_result.json 2>/dev/null || true

# Clean up raw output (sometimes rails runner outputs logs/deprecation warnings)
# We find the last line that looks like JSON
cat /tmp/rails_result.json | grep "^{" | tail -n 1 > /tmp/clean_result.json

# 3. Construct final result JSON
# Merge timestamps with rails result
jq -s '.[0] * .[1]' \
  <(echo "{\"task_start\": $TASK_START, \"task_end\": $TASK_END, \"screenshot_path\": \"/tmp/task_final.png\"}") \
  /tmp/clean_result.json > /tmp/task_result.json

chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json