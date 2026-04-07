#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Refactor and Split Task Results ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Context Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_WP_ID=$(cat /tmp/target_wp_id.txt 2>/dev/null || echo "0")

# 3. Ruby Script to Analyze State
# We need to check:
# - The Original WP (by ID): check subject, estimate
# - The New WP (by Subject search): check estimate, assignee, project, created_at
# - The Relation: check if they are linked

RUBY_SCRIPT=$(cat <<EOF
require 'json'

original_id = $ORIGINAL_WP_ID
task_start = Time.at($TASK_START)

result = {
  original_wp: nil,
  new_wp: nil,
  relation_exists: false,
  timestamp_valid: false
}

# --- Analyze Original WP ---
begin
  wp1 = WorkPackage.find(original_id)
  result[:original_wp] = {
    id: wp1.id,
    subject: wp1.subject,
    estimated_hours: wp1.estimated_hours,
    updated_at: wp1.updated_at.to_i
  }
rescue ActiveRecord::RecordNotFound
  result[:error] = "Original WP not found"
end

# --- Find New WP ---
# Look for the expected frontend subject created AFTER task start
# We relax the search slightly to be case-insensitive or exact
target_subject = "Implement product search (Frontend)"
wp2 = WorkPackage.where(subject: target_subject)
                 .where("created_at > ?", task_start)
                 .last

if wp2
  result[:new_wp] = {
    id: wp2.id,
    subject: wp2.subject,
    estimated_hours: wp2.estimated_hours,
    project_identifier: wp2.project.identifier,
    assignee: wp2.assigned_to ? wp2.assigned_to.name : nil,
    created_at: wp2.created_at.to_i
  }
  
  # --- Check Relation ---
  if result[:original_wp]
    # Check for any relation between wp1 and wp2
    rel = Relation.where(from_id: wp1.id, to_id: wp2.id)
                  .or(Relation.where(from_id: wp2.id, to_id: wp1.id))
                  .first
    if rel
      result[:relation_exists] = true
      result[:relation_type] = rel.relation_type
    end
  end
end

File.write('/tmp/task_result.json', result.to_json)
EOF
)

# 4. Run the analysis inside the container
op_rails "$RUBY_SCRIPT"

# 5. Move result to accessible location and set permissions
if [ -f /tmp/task_result.json ]; then
    cp /tmp/task_result.json /tmp/task_result_final.json
    chmod 666 /tmp/task_result_final.json
else
    echo '{"error": "Failed to generate result JSON"}' > /tmp/task_result_final.json
fi

echo "Result exported to /tmp/task_result_final.json"