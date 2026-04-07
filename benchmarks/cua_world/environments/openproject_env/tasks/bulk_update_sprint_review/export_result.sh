#!/bin/bash
echo "=== Exporting bulk_update_sprint_review results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --------------------------------------------------------------------------
# Extract Data via Rails Runner
# We query the current state of the 3 Work Packages to verify correctness.
# We also fetch updated_at timestamps to ensure changes happened during the task.
# --------------------------------------------------------------------------

RUBY_SCRIPT=$(cat <<EOF
require 'json'

def get_wp_data(subject)
  wp = WorkPackage.find_by(subject: subject)
  return nil unless wp
  
  {
    found: true,
    id: wp.id,
    subject: wp.subject,
    status: wp.status&.name,
    assignee: wp.assigned_to&.name,
    updated_at: wp.updated_at.to_i,
    # Get recent journals (comments/history)
    journals: wp.journals.map { |j| 
      {
        created_at: j.created_at.to_i,
        notes: j.notes.to_s,
        user: j.user&.name
      }
    }
  }
end

result = {
  task_start: $TASK_START,
  task_end: $TASK_END,
  wp1: get_wp_data("Fix broken checkout on mobile Safari"),
  wp2: get_wp_data("Implement product recommendation engine"),
  wp3: get_wp_data("Implement product search with Elasticsearch")
}

puts result.to_json
EOF
)

# Execute Ruby script inside the container
echo "Querying OpenProject database..."
docker exec openproject bash -c "cd /app && bin/rails runner -e production '$RUBY_SCRIPT'" > /tmp/raw_result.json 2>/dev/null

# Clean up output (sometimes rails runner outputs logs/warnings before JSON)
# We look for the last line that looks like JSON
cat /tmp/raw_result.json | grep "^{" | tail -n 1 > /tmp/clean_result.json

# If extraction failed, create a failure fallback
if [ ! -s /tmp/clean_result.json ]; then
    echo "{"error": "Failed to extract data from OpenProject"}" > /tmp/clean_result.json
fi

# Prepare final result file with permissions for the verifier to copy
cp /tmp/clean_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="