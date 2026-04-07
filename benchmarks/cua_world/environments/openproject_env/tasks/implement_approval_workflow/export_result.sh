#!/bin/bash
echo "=== Exporting implement_approval_workflow results ==="

source /workspace/scripts/task_utils.sh

# Target WP ID from setup
WP_ID=$(cat /tmp/target_wp_id.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Generate Ruby verification script
# This script runs INSIDE the OpenProject container
cat > /tmp/verify_internal.rb << RUBYEOF
require 'json'

result = {
  status_exists: false,
  status_created_after_start: false,
  workflow_configured: false,
  wp_moved: false,
  target_wp_id: $WP_ID,
  details: []
}

begin
  # 1. Check if Status exists
  status = Status.find_by(name: 'Awaiting Approval')
  
  if status
    result[:status_exists] = true
    
    # Check creation time (anti-gaming)
    # Ruby Time is in seconds since epoch for comparison
    if status.created_at.to_i > $TASK_START_TIME.to_i
      result[:status_created_after_start] = true
    else
      result[:details] << "Status exists but is too old (pre-dated task start)"
    end
  else
    result[:details] << "Status 'Awaiting Approval' not found"
  end

  # 2. Check Workflow Configuration
  # We look for a transition: Role='Developer', Type='Task', Old='In progress', New='Awaiting Approval'
  
  dev_role = Role.find_by(name: 'Developer')
  task_type = Type.find_by(name: 'Task')
  in_progress = Status.find_by(name: 'In progress')
  
  if status && dev_role && task_type && in_progress
    # The 'workflows' table links these entities.
    # Note: OpenProject uses 'Workflow' model (usually STI, but 'Workflow' base class handles queries)
    # We explicitly check for the transition record.
    exists = Workflow.where(
      role_id: dev_role.id,
      type_id: task_type.id,
      old_status_id: in_progress.id,
      new_status_id: status.id
    ).exists?
    
    if exists
      result[:workflow_configured] = true
    else
      result[:details] << "Workflow transition 'In progress' -> 'Awaiting Approval' not found for Developer/Task"
    end
  else
    result[:details] << "Missing prerequisites for workflow check (Role/Type/Status not found)"
  end

  # 3. Check Work Package State
  if $WP_ID > 0
    wp = WorkPackage.find_by(id: $WP_ID)
    if wp
      if status && wp.status_id == status.id
        result[:wp_moved] = true
      else
        current = wp.status ? wp.status.name : "None"
        result[:details] << "Work Package status is '#{current}', expected 'Awaiting Approval'"
      end
    end
  end

rescue => e
  result[:details] << "Error in verification script: #{e.message}"
end

puts result.to_json
RUBYEOF

# Run the ruby script inside the container
echo "Running verification script in container..."
JSON_OUTPUT=$(op_rails "$(cat /tmp/verify_internal.rb)")

# Extract JSON from potentially noisy output (Rails runner might output deprecation warnings)
# We look for the JSON structure starting with {
CLEAN_JSON=$(echo "$JSON_OUTPUT" | grep -o '{.*}' | tail -n 1)

if [ -z "$CLEAN_JSON" ]; then
    echo "WARNING: Could not parse JSON from Rails output. Raw output:"
    echo "$JSON_OUTPUT"
    # Create a fallback failure JSON
    CLEAN_JSON='{"status_exists": false, "workflow_configured": false, "wp_moved": false, "details": ["Verification script failed to output valid JSON"]}'
fi

# Save to file for verifier.py to pick up
echo "$CLEAN_JSON" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json