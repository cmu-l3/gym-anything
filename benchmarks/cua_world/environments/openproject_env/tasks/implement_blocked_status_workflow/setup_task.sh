#!/bin/bash
set -e
echo "=== Setting up Implement Blocked Status Workflow task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Ensure the environment is clean (Status 'On Hold' should not exist)
# We use the Rails runner to ensure a clean state if the task is retried
echo "Ensuring clean state..."
op_rails "Status.where(name: 'On Hold').destroy_all"

# Record initial status of the target work package for comparison
# We want to make sure it starts as 'New' or at least not 'On Hold'
echo "Resetting target work package status..."
RUBY_RESET="
  wp = WorkPackage.joins(:project)
                  .where(projects: { identifier: 'ecommerce-platform' })
                  .where('subject LIKE ?', '%Fix broken checkout on mobile Safari%')
                  .first
  if wp
    # Reset to New status (ID 1 usually, or find by name)
    new_status = Status.find_by(name: 'New') || Status.first
    wp.status = new_status
    wp.save!
    puts 'Target WP reset to ' + new_status.name
  else
    puts 'Target WP not found during setup!'
  end
"
op_rails "$RUBY_RESET"

# Launch Firefox to the login page
# We don't auto-login the agent to test their ability to log in as admin
launch_firefox_to "http://localhost:8080/login" 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="