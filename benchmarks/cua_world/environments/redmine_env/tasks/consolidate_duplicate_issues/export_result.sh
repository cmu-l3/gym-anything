#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Redmine via Rails Runner
# We need to know the status and relations of the issues in the target project
cat > /tmp/export_data.rb << 'RUBY'
require 'json'

project = Project.find_by(identifier: 'mobile-app-beta')
result = {
  project_found: !project.nil?,
  issues: []
}

if project
  project.issues.each do |i|
    # Get relations where this issue is the 'from' (duplicates) or 'to' (is duplicated by)
    relations_from = IssueRelation.where(issue_from_id: i.id).map { |r| 
      { type: r.relation_type, target_id: r.issue_to_id, id: r.id } 
    }
    
    result[:issues] << {
      id: i.id,
      subject: i.subject,
      description: i.description,
      status: i.status.name,
      updated_on: i.updated_on.to_i,
      relations_from: relations_from
    }
  end
end

puts result.to_json
RUBY

# Run export script inside container
docker cp /tmp/export_data.rb redmine:/tmp/export_data.rb
OUTPUT_JSON_RAW=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/export_data.rb -e production | grep '^{')

# 3. Save to file
echo "$OUTPUT_JSON_RAW" > /tmp/task_result.json

# 4. Add metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Merge using jq if available, or just append distinct file
# We'll just write a separate metadata file to avoid complex json manipulation in bash
cat > /tmp/task_meta.json << EOF
{
  "task_start_time": $TASK_START,
  "app_was_running": $APP_RUNNING,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json /tmp/task_meta.json 2>/dev/null || true

echo "Export complete. Data size: $(stat -c%s /tmp/task_result.json)"