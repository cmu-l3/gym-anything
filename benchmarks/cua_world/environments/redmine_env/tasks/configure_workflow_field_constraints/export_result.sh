#!/bin/bash
set -euo pipefail
echo "=== Exporting configure_workflow_field_constraints result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# Verify Workflow Permissions via Rails Runner
# ------------------------------------------------------------------
# We run a Ruby script inside the Redmine container to query the database directly.
# This avoids needing to navigate the UI for verification and provides 100% accuracy.

RUBY_VERIFY_SCRIPT="/tmp/verify_workflow.rb"
DB_RESULT_FILE="/tmp/db_result.json"

# Create the Ruby verification script
cat > "$RUBY_VERIFY_SCRIPT" << 'RUBY'
begin
  # 1. Identify IDs for the target configuration
  role = Role.find_by(name: 'Developer')
  tracker = Tracker.find_by(name: 'Support')
  status = IssueStatus.find_by(name: 'Feedback')

  if !role || !tracker || !status
    puts ({
      error: "Missing required Redmine data (Role/Tracker/Status not found)",
      valid_setup: false
    }).to_json
    exit
  end

  # 2. Helper to fetch rule for a specific field
  # WorkflowPermission stores rules: 'required', 'readonly' (or nil/none)
  def get_rule(role, tracker, status, field_name)
    perm = WorkflowPermission.where(
      role_id: role.id,
      tracker_id: tracker.id,
      old_status_id: status.id,
      field_name: field_name
    ).first
    perm ? perm.rule : 'none'
  end

  # 3. Collect results
  # We check the 3 required fields plus 'description' as a control (anti-gaming)
  results = {
    valid_setup: true,
    assignee_rule: get_rule(role, tracker, status, 'assigned_to_id'),
    priority_rule: get_rule(role, tracker, status, 'priority_id'),
    subject_rule:  get_rule(role, tracker, status, 'subject'),
    desc_rule:     get_rule(role, tracker, status, 'description')
  }

  puts results.to_json
rescue => e
  puts ({ error: e.message, backtrace: e.backtrace }).to_json
end
RUBY

# Copy script to container
docker cp "$RUBY_VERIFY_SCRIPT" redmine:/tmp/verify_workflow.rb

# Execute script
echo "Running verification script in Redmine container..."
# We use SECRET_KEY_BASE dummy var to satisfy Rails env if needed
docker exec -e SECRET_KEY_BASE="xyz" redmine \
  bundle exec rails runner /tmp/verify_workflow.rb > "$DB_RESULT_FILE" 2>/dev/null || true

# Check if DB result was created and is valid JSON
DB_DATA="{}"
if [ -f "$DB_RESULT_FILE" ] && jq -e . "$DB_RESULT_FILE" >/dev/null 2>&1; then
  DB_DATA=$(cat "$DB_RESULT_FILE")
  echo "Database verification successful."
else
  echo "WARNING: Database verification script failed or produced invalid JSON."
  # Try to grab raw output for debugging
  cat "$DB_RESULT_FILE" 2>/dev/null || true
  DB_DATA='{"error": "Failed to execute rails runner verification"}'
fi

# Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# ------------------------------------------------------------------
# Construct Final Result JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_verification": $DB_DATA
}
EOF

# Move to final location (accessible to host via copy_from_env)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="