#!/bin/bash
# Task setup: assign_work_package
# Resets push notification WP assignee to Bob Smith (as stated in task),
# then navigates to the work package.

source /workspace/scripts/task_utils.sh

echo "=== Setting up assign_work_package task ==="

wait_for_openproject

# Ensure the WP is assigned to Bob Smith initially (so agent must change it to Carol)
WP_ID=$(get_wp_id "mobile-banking-app" "push notification")
if [ -n "$WP_ID" ]; then
    docker exec openproject bash -c "
        cd /app && bundle exec rails runner \"
wp = WorkPackage.find_by(id: ${WP_ID})
bob = User.find_by(login: 'bob.smith')
if wp && bob
  wp.assigned_to = bob
  wp.save!(validate: false)
  puts 'Reset assignee to bob.smith'
end
\" 2>/dev/null" 2>/dev/null || echo "Note: assignee reset failed (non-fatal)"
fi

sleep 2

if [ -n "$WP_ID" ]; then
    echo "Found work package ID: $WP_ID"
    launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/work_packages/${WP_ID}/activity" 5
else
    echo "Warning: Could not find WP ID, navigating to work packages list"
    launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/work_packages" 5
fi

take_screenshot /tmp/task_assign_wp_start.png

echo "=== Task setup complete: assign_work_package ==="
