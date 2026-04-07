#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database state using Rails runner to get definitive workflow configuration
cat > /tmp/verify_workflow.rb << 'RUBY'
begin
  t_target = Tracker.find_by(name: 'Safety Critical Change')
  role = Role.find_by(name: 'Junior Engineer')
  s_new = IssueStatus.find_by(name: 'New')
  s_review = IssueStatus.find_by(name: 'Review')
  s_approved = IssueStatus.find_by(name: 'Approved')

  if !t_target || !role || !s_new || !s_review || !s_approved
    puts ({ error: "Missing required entities in DB" }).to_json
    exit
  end

  # Check total transitions for this tracker (did they copy properly?)
  total_transitions = WorkflowTransition.where(tracker_id: t_target.id, role_id: role.id).count

  # Check specific forbidden transition: New -> Approved
  forbidden_exists = WorkflowTransition.exists?(
    tracker_id: t_target.id,
    role_id: role.id,
    old_status_id: s_new.id,
    new_status_id: s_approved.id
  )

  # Check specific required transition: New -> Review
  required_exists = WorkflowTransition.exists?(
    tracker_id: t_target.id,
    role_id: role.id,
    old_status_id: s_new.id,
    new_status_id: s_review.id
  )

  result = {
    workflow_populated: total_transitions > 0,
    total_transitions_count: total_transitions,
    forbidden_transition_exists: forbidden_exists,
    required_transition_exists: required_exists,
    tracker_name: t_target.name,
    role_name: role.name
  }

  puts result.to_json
rescue => e
  puts ({ error: e.message }).to_json
end
RUBY

# Run verification script
echo "Running verification query..."
docker cp /tmp/verify_workflow.rb redmine:/tmp/
QUERY_RESULT=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/verify_workflow.rb || echo '{"error": "Rails runner failed"}')

# Clean up JSON (extract only the JSON part if there's noise)
JSON_CLEAN=$(echo "$QUERY_RESULT" | grep -o '{.*}' | tail -n 1 || echo '{"error": "Invalid JSON output"}')

# Combine with system metrics
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "db_state": $JSON_CLEAN,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="