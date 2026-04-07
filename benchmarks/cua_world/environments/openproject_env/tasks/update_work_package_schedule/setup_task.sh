#!/bin/bash
# Setup script for update_work_package_schedule
# Ensures the target work package exists and is in a clean state (no dates/hours set).
# Sets the progress calculation mode to 'manual' so the agent can edit % Complete.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up update_work_package_schedule task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Wait for OpenProject to be ready
wait_for_openproject

# 3. Configure OpenProject & Reset Target Work Package
# We use Rails runner to:
# - Set Done Ratio mode to 'field' (allows manual editing)
# - Find the target WP
# - Reset its scheduling fields to nil/0 so the agent has to actually set them
echo "Configuring work package state..."
docker exec openproject bash -c "cd /app && bundle exec rails runner \"
begin
  # 1. Allow manual editing of % Complete
  Setting.work_package_done_ratio = 'field'
  puts 'INFO: Done ratio mode set to field'

  # 2. Reset the target work package
  wp = WorkPackage.joins(:project)
        .where(projects: {identifier: 'ecommerce-platform'})
        .where('work_packages.subject LIKE ?', '%product recommendation engine%')
        .first

  if wp
    puts 'INFO: Found target WP ID: ' + wp.id.to_s
    wp.start_date = nil
    wp.due_date = nil
    wp.estimated_hours = nil
    wp.done_ratio = 0
    # Save without validation to ensure we force the state
    wp.save!(validate: false)
    puts 'INFO: Target WP reset successfully'
  else
    puts 'ERROR: Target Work Package not found!'
    exit 1
  end
rescue => e
  puts 'ERROR: ' + e.message
  exit 1
end
\""

# 4. Launch Firefox to the project work packages list
PROJECT_URL="http://localhost:8080/projects/ecommerce-platform/work_packages"
echo "Launching Firefox to $PROJECT_URL..."
launch_firefox_to "$PROJECT_URL" 8

# 5. Maximize window
maximize_firefox

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="