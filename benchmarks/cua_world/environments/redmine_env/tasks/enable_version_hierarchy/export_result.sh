#!/bin/bash
echo "=== Exporting enable_version_hierarchy result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# EXTRACT DATA FROM REDMINE DB
# ============================================================
# We need to verify:
# 1. The parent project's version "Phase 1 Launch" has sharing != 'none'
# 2. The subproject's issue "Main Thruster Design" has fixed_version_id == "Phase 1 Launch" ID

cat > /tmp/verify_state.rb << 'RB_EOF'
require 'json'

begin
  parent = Project.find_by(identifier: 'orbital-platform')
  child = Project.find_by(identifier: 'propulsion-system')
  version = parent.versions.find_by(name: 'Phase 1 Launch')
  issue = child.issues.find_by(subject: 'Main Thruster Design')

  result = {
    parent_exists: !parent.nil?,
    child_exists: !child.nil?,
    version_exists: !version.nil?,
    issue_exists: !issue.nil?,
    
    # Verification criteria
    version_sharing: version ? version.sharing : 'nil',
    version_id: version ? version.id : nil,
    issue_fixed_version_id: issue ? issue.fixed_version_id : nil,
    
    # Extra debug info
    parent_name: parent ? parent.name : '',
    issue_subject: issue ? issue.subject : ''
  }

  puts result.to_json
rescue => e
  puts({ error: e.message }.to_json)
end
RB_EOF

# Execute verification script
docker cp /tmp/verify_state.rb redmine:/tmp/verify_state.rb
OUTPUT_JSON=$(docker exec -e RAILS_ENV=production redmine bundle exec rails runner /tmp/verify_state.rb)

# Extract JSON from potential Rails noise (grab last line usually, or look for {)
CLEAN_JSON=$(echo "$OUTPUT_JSON" | grep -o '{.*}' | tail -n 1)

# Save to result file
echo "$CLEAN_JSON" > /tmp/db_state.json

# Create final result structure
cat > /tmp/task_result.json << EOF
{
  "timestamp": "$(date -Iseconds)",
  "db_state": $CLEAN_JSON,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json