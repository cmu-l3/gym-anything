#!/bin/bash
set -e
echo "=== Exporting manage_release_carryover results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png
log "Final screenshot captured."

# 2. Extract verification data from Redmine
# We need to check the current state of the issues and version
echo "Querying Redmine for final state..."

cat > /tmp/verify_task.rb << 'RUBY'
require 'json'

# Load the initial setup data to know which IDs to check
setup_data = JSON.parse(File.read('/tmp/task_setup_data.json'))

ids_to_keep = setup_data['ids_to_keep']
ids_to_move = setup_data['ids_to_move']
source_version_id = setup_data['source_version_id']

# Check Source Version Status
v_source = Version.find_by(id: source_version_id)
source_version_status = v_source ? v_source.status : 'not_found'

# Check Issues that should have STAYED (Closed issues)
# We expect them to still be in source_version_id
kept_issues_status = ids_to_keep.map do |id|
  issue = Issue.find_by(id: id)
  if issue
    { id: id, fixed_version_id: issue.fixed_version_id, subject: issue.subject }
  else
    { id: id, error: 'not_found' }
  end
end

# Check Issues that should have MOVED (Open issues)
# We expect them to NOT be in source_version_id (ideally in target, but definitely not source)
moved_issues_status = ids_to_move.map do |id|
  issue = Issue.find_by(id: id)
  if issue
    { id: id, fixed_version_id: issue.fixed_version_id, subject: issue.subject }
  else
    { id: id, error: 'not_found' }
  end
end

result = {
  setup_data: setup_data,
  final_state: {
    source_version_status: source_version_status,
    kept_issues: kept_issues_status,
    moved_issues: moved_issues_status
  },
  timestamp: Time.now.to_i
}

puts result.to_json
RUBY

# Run verification script inside container
docker cp /tmp/verify_task.rb redmine:/tmp/verify_task.rb
# We capture stdout to a file. Note: rails runner might output logs, so we filter for JSON if needed.
# But usually runner output is clean if we control it.
VERIFY_OUTPUT=$(docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bundle exec rails runner /tmp/verify_task.rb | tail -n 1)

# Validate JSON
if echo "$VERIFY_OUTPUT" | jq . >/dev/null 2>&1; then
    echo "$VERIFY_OUTPUT" > /tmp/task_result.json
    echo "Verification data exported successfully."
else
    echo "ERROR: Failed to get valid JSON from verification script."
    echo "Raw output: $VERIFY_OUTPUT"
    # Create a fallback failure result
    echo '{"error": "verification_script_failed"}' > /tmp/task_result.json
fi

# 3. Add screenshot path and basic app info
# We modify the json to include the screenshot path for the host verifier
jq '. + {"screenshot_path": "/tmp/task_final.png"}' /tmp/task_result.json > /tmp/task_result_final.json
mv /tmp/task_result_final.json /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "=== Export complete ==="