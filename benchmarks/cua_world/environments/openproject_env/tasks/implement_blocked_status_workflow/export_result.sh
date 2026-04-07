#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Run verification logic INSIDE the container via Rails runner
# This is crucial because the host verifier cannot execute commands in the container.
# We gather all necessary data here and export it as JSON.

echo "Running internal verification script..."
RUBY_VERIFY="
  require 'json'
  
  result = {
    status_created: false,
    workflow_configured: false,
    wp_updated: false,
    integrity_check: true,
    details: []
  }

  # Check 1: Status 'On Hold' exists
  on_hold = Status.find_by(name: 'On Hold')
  if on_hold
    result[:status_created] = true
  else
    result[:details] << 'Status On Hold not found'
  end

  # Check 2: Workflow configuration
  # We check if there are workflow transitions defined for Developer (role) + Bug (type) -> On Hold
  if on_hold
    # Find IDs
    developer = Role.find_by(name: 'Developer')
    bug = Type.find_by(name: 'Bug')
    
    if developer && bug
      # Check for transitions to On Hold (new_status_id = on_hold.id)
      # for the specific role and type
      flows = Workflow.where(role_id: developer.id, type_id: bug.id, new_status_id: on_hold.id)
      
      if flows.exists?
        result[:workflow_configured] = true
      else
        result[:details] << 'No workflow transition found for Developer/Bug leading to On Hold'
      end
    else
      result[:details] << 'Developer role or Bug type missing (unexpected environment state)'
    end
  end

  # Check 3: Work Package updated
  wp = WorkPackage.joins(:project)
                  .where(projects: { identifier: 'ecommerce-platform' })
                  .where('subject LIKE ?', '%Fix broken checkout on mobile Safari%')
                  .first
  
  if wp
    if wp.status.name == 'On Hold'
      result[:wp_updated] = true
    else
      result[:details] << \"Work Package status is #{wp.status.name}, expected On Hold\"
    end
  else
    result[:details] << 'Target work package not found'
  end

  # Check 4: Integrity (Prevent renaming 'New' to 'On Hold')
  # If 'New' is missing, they might have renamed it instead of creating a new one
  if !Status.find_by(name: 'New')
    result[:integrity_check] = false
    result[:details] << 'Status New is missing (suspected renaming)'
  end

  puts '___JSON_START___'
  puts result.to_json
  puts '___JSON_END___'
"

# Execute the ruby script and capture output
RAW_OUTPUT=$(op_rails "$RUBY_VERIFY")

# Extract JSON part
JSON_OUTPUT=$(echo "$RAW_OUTPUT" | sed -n '/___JSON_START___/,/___JSON_END___/p' | sed '1d;$d')

# Save to a temporary file first
echo "$JSON_OUTPUT" > /tmp/internal_verification.json

# 3. Create the final export JSON for the host verifier
# We wrap the internal verification results with file timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create final JSON structure
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "screenshot_path": "/tmp/task_final.png",
  "internal_verification": $(cat /tmp/internal_verification.json || echo "{}")
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json