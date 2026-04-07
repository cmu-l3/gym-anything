#!/bin/bash
# Export script for bulk_tag_work_packages
# Runs a ruby script to verify the state of tags on work packages.

source /workspace/scripts/task_utils.sh

echo "=== Exporting bulk_tag_work_packages result ==="

# 1. Capture Final Screenshot (Evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Run Verification Logic in Container
# We extract the state of all work packages in the project to verify Precision and Recall.
# We create a JSON object containing lists of IDs.

cat > /tmp/verify_tags.rb << 'RUBY_EOF'
require 'json'

project = Project.find_by(identifier: 'ecommerce-platform')
target_tag = 'search-initiative'
search_term = 'search'

# Find all WPs in project
all_wps = project.work_packages

# Categorize WPs based on Subject (Ground Truth)
# We use ILIKE logic or generic ruby downcase check
targets = all_wps.select { |wp| wp.subject.downcase.include?(search_term) }
non_targets = all_wps.select { |wp| !wp.subject.downcase.include?(search_term) }

# Check actual tags
tagged_wps = all_wps.select { |wp| wp.tags.map(&:name).include?(target_tag) }

# Check if tag exists in system
tag_obj = Tag.find_by(name: target_tag)

result = {
  target_ids: targets.map(&:id),
  non_target_ids: non_targets.map(&:id),
  tagged_ids: tagged_wps.map(&:id),
  tag_exists: !tag_obj.nil?,
  target_subjects: targets.map(&:subject),
  tagged_subjects: tagged_wps.map(&:subject)
}

puts "__JSON_START__"
puts result.to_json
puts "__JSON_END__"
RUBY_EOF

# Run script and capture output
echo "Running verification script in container..."
RAW_OUTPUT=$(op_rails "$(cat /tmp/verify_tags.rb)")

# Extract JSON from potential rails noise
JSON_CONTENT=$(echo "$RAW_OUTPUT" | sed -n '/__JSON_START__/,/__JSON_END__/p' | sed '1d;$d')

# Save to file
echo "$JSON_CONTENT" > /tmp/task_result.json

# 3. Add timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Merge timestamp into result (using python for safety)
python3 -c "
import json
import os

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['screenshot_path'] = '/tmp/task_final.png'

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="