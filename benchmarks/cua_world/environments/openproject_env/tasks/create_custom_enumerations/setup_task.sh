#!/bin/bash
# Setup for create_custom_enumerations task
# Ensures OpenProject is running and Firefox is open at the login page

set -e
echo "=== Setting up create_custom_enumerations task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Record initial enumeration counts for anti-gaming verification
# We execute a rails runner script inside the container to get the counts
echo "Recording initial state..."
docker exec openproject bash -lc "cd /app && bin/rails runner -e production '
  puts \"PRIORITIES:#{IssuePriority.count}\"
  puts \"ACTIVITIES:#{TimeEntryActivity.count}\"
  wp = WorkPackage.find_by(subject: \"Fix broken checkout on mobile Safari\")
  puts \"WP_PRIORITY:#{wp ? wp.priority.name : \"None\"}\"
'" > /tmp/initial_state_raw.txt 2>/dev/null || true

# Parse the raw output into individual files for the export script to use later
grep "PRIORITIES:" /tmp/initial_state_raw.txt | cut -d':' -f2 > /tmp/initial_priority_count.txt
grep "ACTIVITIES:" /tmp/initial_state_raw.txt | cut -d':' -f2 > /tmp/initial_activity_count.txt
grep "WP_PRIORITY:" /tmp/initial_state_raw.txt | cut -d':' -f2 > /tmp/initial_wp_priority.txt

echo "Initial Setup State:"
echo "  Priorities: $(cat /tmp/initial_priority_count.txt)"
echo "  Activities: $(cat /tmp/initial_activity_count.txt)"
echo "  WP Priority: $(cat /tmp/initial_wp_priority.txt)"

# Launch Firefox to OpenProject login page
# The user needs to login as admin to perform administration tasks
launch_firefox_to "http://localhost:8080/login" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="