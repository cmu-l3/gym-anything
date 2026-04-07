#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# We use Rails runner to extract the exact state of the database into a JSON object.
# This runs inside the Docker container.
echo "Querying OpenProject database state..."

RUBY_SCRIPT=$(cat <<EOF
require 'json'

result = {
  task_start_time: $TASK_START,
  group_found: false,
  group_created_at: 0,
  member_logins: [],
  project_member: false,
  role_names: []
}

begin
  # Check group
  g = Group.find_by(lastname: 'QA Team')
  
  if g
    result[:group_found] = true
    result[:group_created_at] = g.created_at.to_i
    result[:member_logins] = g.users.map(&:login).sort
    
    # Check project membership
    proj = Project.find_by(identifier: 'mobile-banking-app')
    if proj
      # Look for membership of the Group principal in the project
      pm = Member.find_by(project: proj, principal: g)
      if pm
        result[:project_member] = true
        result[:role_names] = pm.roles.map(&:name)
      end
    end
  end
rescue => e
  result[:error] = e.message
end

puts JSON.generate(result)
EOF
)

# Run the ruby script inside the container and capture output
# op_rails function wraps "docker exec ... rails runner ..."
# We pipe the output to a temp file, then clean it (rails runner might output log lines)
TEMP_OUTPUT=$(mktemp)
op_rails "$RUBY_SCRIPT" > "$TEMP_OUTPUT" 2>/dev/null

# Extract the JSON line (usually the last line of output)
JSON_RESULT=$(tail -n 1 "$TEMP_OUTPUT")

# Verify it looks like JSON
if [[ ! "$JSON_RESULT" =~ ^\{ ]]; then
    echo "WARNING: Failed to capture valid JSON from Rails runner. Raw output:"
    cat "$TEMP_OUTPUT"
    # Fallback empty JSON to prevent verifier crash
    JSON_RESULT="{}"
fi

# Save to the final result file
echo "$JSON_RESULT" > /tmp/task_result.json

# Cleanup
rm -f "$TEMP_OUTPUT"

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="