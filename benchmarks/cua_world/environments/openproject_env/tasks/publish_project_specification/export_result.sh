#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting results for publish_project_specification@1 ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define Rails verification script
# This script runs inside the container and checks the database state
# It outputs a JSON object with all necessary verification data
VERIFY_SCRIPT=$(cat <<EOF
require 'json'

result = {
  module_enabled: false,
  category_exists: false,
  document_exists: false,
  category_correct: false,
  file_attached: false,
  timestamps_valid: false
}

begin
  # Check 1: Module Enabled
  p = Project.find_by(identifier: 'mobile-banking-app')
  if p && p.enabled_modules.exists?(name: 'documents')
    result[:module_enabled] = true
  end

  # Check 2: Category Exists
  cat = DocumentCategory.find_by(name: 'Specifications')
  if cat
    result[:category_exists] = true
  end

  # Check 3: Document Created
  # We check for the specific title in the specific project
  doc = Document.find_by(project: p, title: 'Mobile App Specification v1')
  
  if doc
    result[:document_exists] = true
    
    # Check 4: Document Category Link
    if cat && doc.category_id == cat.id
      result[:category_correct] = true
    end
    
    # Check 5: Attachment
    # Check if any attachment matches the filename
    if doc.attachments.any? { |a| a.filename == 'mobile_spec_v1.txt' }
      result[:file_attached] = true
    end

    # Check 6: Timestamps (Anti-gaming)
    # Ensure creation happened after task start
    # We pass task start time from bash, but simple "recent" check is usually enough
    # Here we just return the timestamp for the python verifier to check
    result[:doc_created_at] = doc.created_at.to_i
    result[:cat_created_at] = cat ? cat.created_at.to_i : 0
  end
rescue => e
  result[:error] = e.message
end

puts JSON.generate(result)
EOF
)

# 3. Execute Rails Runner
echo "Running verification query..."
JSON_OUTPUT=$(op_rails "$VERIFY_SCRIPT")

# 4. Save result to a temp file, then move to final location
# (Handle potential empty output or errors)
if [ -z "$JSON_OUTPUT" ]; then
    echo '{"error": "No output from Rails runner"}' > /tmp/raw_result.json
else
    # Extract the last line in case of noise
    echo "$JSON_OUTPUT" | tail -n 1 > /tmp/raw_result.json
fi

# 5. Add Task Metadata (start time) to the JSON
# We use python to merge the rails output with shell variables
python3 -c "
import json
import os
import time

try:
    with open('/tmp/raw_result.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {'error': 'Failed to parse Rails output'}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except:
    start_time = int(time.time())

data['task_start_time'] = start_time
data['screenshot_path'] = '/tmp/task_final.png'

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 6. Cleanup and permissions
chmod 666 /tmp/task_result.json
rm -f /tmp/raw_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="