#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting configure_workflow_transitions results ==="

REDMINE_SKB="redmine_env_secret_key_base_do_not_use_in_production_xyz123"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current workflow state
echo "Querying current workflow transitions for Support/Developer..."
CURRENT_STATE=$(docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bundle exec rails runner "
    tracker = Tracker.find_by(name: 'Support')
    role = Role.find_by(name: 'Developer')
    if tracker && role
      transitions = WorkflowTransition.where(tracker_id: tracker.id, role_id: role.id)
      statuses = IssueStatus.all.index_by(&:id)
      # Return simply [from, to] pairs for easy parsing
      result = transitions.map { |t| { from: statuses[t.old_status_id]&.name, to: statuses[t.new_status_id]&.name } }
      puts JSON.generate({ transitions: result, count: result.size })
    else
      puts JSON.generate({ error: 'Tracker or role not found', transitions: [], count: 0 })
    end
  " -e production 2>/dev/null | grep '^{' | head -1)

if [ -z "$CURRENT_STATE" ]; then
  CURRENT_STATE='{"transitions":[],"count":0, "error": "Query failed"}'
fi

# Load initial state
INITIAL_STATE=$(cat /tmp/initial_workflow_state.json 2>/dev/null || echo '{"transitions":[],"count":0}')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_state": $INITIAL_STATE,
    "current_state": $CURRENT_STATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="