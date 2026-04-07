#!/bin/bash
set -e
echo "=== Setting up implement_approval_workflow task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenProject is up
wait_for_openproject

# --- 1. Identify Target Work Package ---
# We use the helper to find "Implement product search with Elasticsearch"
WP_ID=$(get_wp_id "ecommerce-platform" "Elasticsearch")

if [ -z "$WP_ID" ]; then
    echo "ERROR: Target work package not found during setup."
    exit 1
fi
echo "Target Work Package ID: $WP_ID"
echo "$WP_ID" > /tmp/target_wp_id.txt

# --- 2. Ensure WP is in 'In Progress' State ---
# We use Rails runner to force the state, ensuring the starting condition is valid
# even if the seed data drifted or previous runs modified it.
echo "Resetting WP #$WP_ID to 'In Progress'..."
cat > /tmp/reset_wp.rb << RUBYEOF
begin
  wp = WorkPackage.find($WP_ID)
  status = Status.find_by(name: 'In progress')
  if status
    wp.status = status
    wp.save!(validate: false) # Skip validation to force the state
    puts "WP reset to In Progress (id: #{status.id})"
  else
    puts "Error: 'In progress' status not found"
  end
rescue => e
  puts "Error resetting WP: #{e.message}"
end
RUBYEOF

op_rails "$(cat /tmp/reset_wp.rb)"

# --- 3. Launch Firefox ---
# Start at the administration overview to save some navigation clicks
# but leave the specific path (Statuses/Workflow) to the agent.
launch_firefox_to "${OP_URL}/admin" 5

# --- 4. Initial Evidence ---
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="