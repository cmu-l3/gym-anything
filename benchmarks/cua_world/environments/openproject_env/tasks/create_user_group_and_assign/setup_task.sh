#!/bin/bash
set -e
echo "=== Setting up task: create_user_group_and_assign ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Ensure no group named "QA Team" exists (clean state)
echo "Cleaning up any pre-existing QA Team group..."
op_rails "
g = Group.find_by(lastname: 'QA Team')
if g
  g.destroy
  puts 'Removed pre-existing QA Team group'
else
  puts 'No pre-existing QA Team group found'
end
"

# Launch Firefox at OpenProject home page (admin is already logged in via cookie from setup)
# We navigate to the home page so the agent has to find the Administration panel
launch_firefox_to "http://localhost:8080/my/page" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="