#!/bin/bash
# Setup script for enforce_strong_password_policy task

source /workspace/scripts/task_utils.sh

echo "=== Setting up enforce_strong_password_policy task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenProject is up
wait_for_openproject

# Reset password policy to a known weak state (to ensure the agent actually changes it)
# Default usually allows shorter passwords. We'll set it to something distinct like 6 chars, no complexity.
echo "Resetting password policy to weak default..."
op_rails "
  Setting.password_min_length = 6
  Setting.password_active_rules = []
"

# Launch Firefox to the Administration dashboard (or login page if not logged in)
# We navigate to /admin which usually redirects to login if not authenticated
launch_firefox_to "http://localhost:8080/admin" 5

# Maximize for visibility
maximize_firefox

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="