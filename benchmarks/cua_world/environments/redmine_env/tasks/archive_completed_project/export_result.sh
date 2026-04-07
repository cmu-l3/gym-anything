#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting archive_completed_project result ==="

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Prepare checking script
cat > /tmp/check_project_status.rb << 'EOF'
require 'json'

begin
  p = Project.find_by(identifier: 'office-relocation-2024')
  
  if p.nil?
    result = { found: false }
  else
    # 1=Active, 5=Closed, 9=Archived
    status_code = p.status
    
    # Check open issues
    # IssueStatus.where(is_closed: false) returns all open statuses
    open_issues_count = Issue.where(project_id: p.id).joins(:status).where(issue_statuses: { is_closed: false }).count
    
    # Check for specific note in journals
    # We look for journals on issues in this project containing the phrase
    note_fragment = "Project completed, task cancelled"
    matching_notes = Journal.joins(:issue)
                            .where(issues: { project_id: p.id })
                            .where("notes LIKE ?", "%#{note_fragment}%")
                            .count
                            
    # Check timestamps of these notes (to ensure they are recent)
    # We'll just return the max created_on to compare with task start in python
    last_note_time = Journal.joins(:issue)
                            .where(issues: { project_id: p.id })
                            .where("notes LIKE ?", "%#{note_fragment}%")
                            .maximum(:created_on)
                            
    result = {
      found: true,
      status_code: status_code,
      open_issues_count: open_issues_count,
      matching_notes_count: matching_notes,
      last_note_timestamp: last_note_time ? last_note_time.to_i : 0
    }
  end
rescue => e
  result = { found: false, error: e.message }
end

puts JSON.generate(result)
EOF

# Run check inside container
echo "Running validation script..."
docker cp /tmp/check_project_status.rb redmine:/tmp/
OUTPUT_JSON=$(docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/check_project_status.rb)

# Save to file
echo "$OUTPUT_JSON" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="