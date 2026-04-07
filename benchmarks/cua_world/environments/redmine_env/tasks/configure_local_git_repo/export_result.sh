#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Git Repo result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Redmine internal state via Rails runner
# We output the JSON directly from Rails to a file inside the container, 
# then cat it to a file on the VM.
echo "Querying Rails state..."

CONTAINER_JSON="/tmp/rails_result.json"
VM_JSON="/tmp/task_result.json"

RUBY_SCRIPT="
  p = Project.find_by(identifier: 'core-engine')
  result = {
    project_found: !p.nil?
  }
  
  if p
    result[:enabled_modules] = p.enabled_module_names
    
    # Check for repository
    repo = p.repository
    if repo
      result[:repo_exists] = true
      result[:repo_type] = repo.type
      result[:repo_url] = repo.url
      result[:repo_identifier] = repo.identifier
    else
      result[:repo_exists] = false
    end
  end
  
  File.write('$CONTAINER_JSON', result.to_json)
"

# Run the query
docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine bundle exec rails runner "$RUBY_SCRIPT"

# Extract the JSON from container to VM
docker exec redmine cat "$CONTAINER_JSON" > "$VM_JSON"

# Append timestamp info to the JSON (using jq to merge)
# If jq is not available, we use python
if command -v jq >/dev/null 2>&1; then
  jq --argjson start "$TASK_START" --argjson end "$TASK_END" \
     '. + {task_start: $start, task_end: $end}' "$VM_JSON" > "${VM_JSON}.tmp" && mv "${VM_JSON}.tmp" "$VM_JSON"
else
  # Fallback python merge
  python3 -c "
import json
with open('$VM_JSON', 'r') as f:
    data = json.load(f)
data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
with open('$VM_JSON', 'w') as f:
    json.dump(data, f)
"
fi

echo "Result exported to $VM_JSON"
cat "$VM_JSON"
echo ""
echo "=== Export complete ==="