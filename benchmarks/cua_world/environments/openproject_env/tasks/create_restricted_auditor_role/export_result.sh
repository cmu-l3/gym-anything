#!/bin/bash
echo "=== Exporting create_restricted_auditor_role result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract final state via Rails runner
# We need to know:
# - Does the role exist?
# - What permissions does it have?
# - What roles does Carol have on the project?

echo "Querying OpenProject database..."
RUBY_SCRIPT=$(cat <<EOF
require 'json'

result = {
  role_exists: false,
  role_permissions: [],
  user_roles: [],
  user_found: false,
  project_found: false
}

# Check Role
role = Role.find_by(name: 'External Auditor')
if role
  result[:role_exists] = true
  # Convert symbols to strings
  result[:role_permissions] = role.permissions.map(&:to_s)
end

# Check User Assignment
u = User.find_by(login: 'carol.williams')
p = Project.find_by(identifier: 'ecommerce-platform')

if u
  result[:user_found] = true
end

if p
  result[:project_found] = true
end

if u && p
  member = Member.find_by(project: p, principal: u)
  if member
    result[:user_roles] = member.roles.map(&:name)
  end
end

puts JSON.generate(result)
EOF
)

# Run the script inside the container and capture output
# We use a temp file to store the JSON output from the container execution
op_rails "$RUBY_SCRIPT" > /tmp/rails_output.txt 2>/dev/null

# Extract the last line which should be the JSON
JSON_OUTPUT=$(tail -n 1 /tmp/rails_output.txt)

# Validate if it looks like JSON
if [[ ! "$JSON_OUTPUT" =~ ^\{ ]]; then
    echo "Error: Rails output does not look like JSON"
    echo "$JSON_OUTPUT"
    # Fallback default
    JSON_OUTPUT='{"error": "Failed to retrieve data"}'
fi

# 3. Create final result JSON file
cat > /tmp/task_result.json <<EOF
{
    "timestamp": "$(date +%s)",
    "rails_data": $JSON_OUTPUT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so the host can read it (if mapped, though copy_from_env handles this)
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="