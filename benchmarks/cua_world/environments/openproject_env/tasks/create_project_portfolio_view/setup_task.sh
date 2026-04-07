#!/bin/bash
echo "=== Setting up Create Project Portfolio View task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure OpenProject is ready
wait_for_openproject

# 3. Clean up any existing query with this name to ensure a fresh start
echo "Cleaning up old queries..."
op_rails "Query.where(name: 'PMO Portfolio').destroy_all"

# 4. Automate Login as Admin
# We need to ensure the agent starts logged in as Admin to create public queries
echo "Logging in as admin..."
launch_firefox_to "http://localhost:8080/login" 5

# Type credentials
su - ga -c "DISPLAY=:1 xdotool type 'admin'"
su - ga -c "DISPLAY=:1 xdotool key Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'Admin1234!'"
su - ga -c "DISPLAY=:1 xdotool key Return"

# Wait for login to complete
sleep 5

# 5. Navigate to the global Projects list
# The global projects list is usually at /projects
navigate_to "http://localhost:8080/projects" 5

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="