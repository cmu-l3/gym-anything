#!/bin/bash
# Export script for integrate_git_repository task

source /workspace/scripts/task_utils.sh

echo "=== Exporting integrate_git_repository results ==="

# 1. Record end timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Query OpenProject state via Rails Runner
#    We check:
#    - Is 'repository' in enabled_modules?
#    - Does project.repository exist?
#    - Is type Git?
#    - Is path correct?

echo "Querying OpenProject database configuration..."
RUBY_CHECK_SCRIPT="
require 'json'
begin
  p = Project.find_by(identifier: 'devops-automation')
  if p
    mod_enabled = p.enabled_modules.map(&:name).include?('repository')
    repo = p.repository
    
    # Handle different class name conventions (Repository::Git or just Git)
    scm_type = repo ? repo.scm_type.to_s : nil
    
    # URL/Path can be stored in url or root_url depending on version
    path = repo ? (repo.url || repo.root_url) : nil
    
    result = {
      project_found: true,
      module_enabled: mod_enabled,
      repository_configured: !repo.nil?,
      scm_type: scm_type,
      repository_path: path
    }
  else
    result = { project_found: false }
  end
  puts result.to_json
rescue => e
  puts({ error: e.message }.to_json)
end
"

# Execute ruby script inside container
DB_RESULT_JSON=$(docker exec openproject bash -c "cd /app && bundle exec rails runner \"$RUBY_CHECK_SCRIPT\"" 2>/dev/null)

# Clean up output (sometimes rails runner outputs logs before json)
# Extract the last line which should be the JSON
CLEAN_JSON=$(echo "$DB_RESULT_JSON" | tail -n 1)

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": $CLEAN_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="