#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_workflow_transitions task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is reachable
if ! wait_for_http "$REDMINE_BASE_URL" 120; then
  echo "ERROR: Redmine is not reachable at $REDMINE_BASE_URL"
  exit 1
fi

REDMINE_SKB="redmine_env_secret_key_base_do_not_use_in_production_xyz123"

# Record the initial (default) workflow state for Support/Developer for anti-gaming comparison
echo "Recording initial workflow state..."
INITIAL_STATE=$(docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bundle exec rails runner "
    tracker = Tracker.find_by(name: 'Support')
    role = Role.find_by(name: 'Developer')
    if tracker && role
      transitions = WorkflowTransition.where(tracker_id: tracker.id, role_id: role.id)
      statuses = IssueStatus.all.index_by(&:id)
      result = transitions.map { |t| { from: statuses[t.old_status_id]&.name, to: statuses[t.new_status_id]&.name } }
      puts JSON.generate({ transitions: result, count: result.size })
    else
      puts JSON.generate({ error: 'Tracker or role not found', transitions: [], count: 0 })
    end
  " -e production 2>/dev/null | grep '^{' | head -1)

echo "$INITIAL_STATE" > /tmp/initial_workflow_state.json
echo "Initial workflow transition count: $(echo "$INITIAL_STATE" | jq '.count' 2>/dev/null || echo 'unknown')"

# Log in as admin and navigate to Redmine home page
ensure_redmine_logged_in "$REDMINE_BASE_URL"
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="