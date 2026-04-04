#!/bin/bash
# Task setup: set_work_package_dates
# Clears existing dates on the blue-green deployment WP, then navigates to it.

source /workspace/scripts/task_utils.sh

echo "=== Setting up set_work_package_dates task ==="

wait_for_openproject

# Get work package ID
WP_ID=$(get_wp_id "devops-automation" "blue-green deployment")

if [ -n "$WP_ID" ]; then
    # Clear existing dates so agent must set them
    docker exec openproject bash -c "
        cd /app && bundle exec rails runner \"
wp = WorkPackage.find_by(id: ${WP_ID})
if wp
  wp.start_date = nil
  wp.due_date = nil
  wp.save!(validate: false)
  puts 'Cleared dates on blue-green WP'
end
\" 2>/dev/null" 2>/dev/null || echo "Note: date clearing failed (non-fatal)"
fi

sleep 2

if [ -n "$WP_ID" ]; then
    echo "Found work package ID: $WP_ID"
    launch_firefox_to "http://localhost:8080/projects/devops-automation/work_packages/${WP_ID}/activity" 5
else
    echo "Warning: Could not find WP ID, navigating to work packages list"
    launch_firefox_to "http://localhost:8080/projects/devops-automation/work_packages" 5
fi

take_screenshot /tmp/task_set_wp_dates_start.png

echo "=== Task setup complete: set_work_package_dates ==="
