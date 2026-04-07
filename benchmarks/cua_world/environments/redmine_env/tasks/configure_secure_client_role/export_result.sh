#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export Role and Membership data using Rails runner
# We extract the specific role "External Reviewer" and the roles assigned to "Jordan Lee" on "Mobile Banking App"
cat > /tmp/export_data.rb << 'RUBY'
require 'json'

result = {
  role_found: false,
  role_data: {},
  membership_found: false,
  membership_roles: []
}

begin
  # Check Role
  role = Role.find_by(name: 'External Reviewer')
  if role
    result[:role_found] = true
    result[:role_data] = {
      name: role.name,
      issues_visibility: role.issues_visibility,
      time_entries_visibility: role.time_entries_visibility,
      users_visibility: role.users_visibility,
      permissions: role.permissions.map(&:to_s)
    }
  end

  # Check Membership
  user = User.find_by(login: 'jordan.lee')
  project = Project.find_by(identifier: 'mobile-banking')
  
  if user && project
    member = Member.find_by(user_id: user.id, project_id: project.id)
    if member
      result[:membership_found] = true
      result[:membership_roles] = member.roles.map(&:name)
    end
  end

rescue => e
  result[:error] = e.message
end

puts result.to_json
RUBY

# Run the export script inside the container
docker cp /tmp/export_data.rb redmine:/tmp/export_data.rb
docker exec -e RAILS_ENV=production redmine bundle exec rails runner /tmp/export_data.rb > /tmp/rails_export.json 2>/dev/null

# Clean up any potential Rails runner noise (sometimes it outputs deprecation warnings)
# We look for the last line that looks like JSON
cat /tmp/rails_export.json | grep "^{" | tail -n 1 > /tmp/clean_export.json

# If grep failed (empty file), ensure we have valid JSON
if [ ! -s /tmp/clean_export.json ]; then
    echo "{}" > /tmp/clean_export.json
fi

# Merge timestamps and screenshot info
jq -s '.[0] * .[1]' /tmp/clean_export.json <(cat <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "screenshot_path": "/tmp/task_final.png"
}
EOF
) > /tmp/task_result.json

# Set permissions so the host can read it
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="