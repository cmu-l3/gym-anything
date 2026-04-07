#!/bin/bash
set -e

echo "=== Setting up task: move_work_package_cross_project ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# -----------------------------------------------------------------------
# Record initial state: verify the WP is in devops-automation
# -----------------------------------------------------------------------
echo "Recording initial work package state..."

# Ruby script to check initial state
cat > /tmp/check_initial.rb << 'RUBY'
require "json"
begin
  wps = WorkPackage.where(subject: "Set up application monitoring and alerting")
  count = wps.count
  if count > 0
    wp = wps.first
    out = {
      found: true,
      count: count,
      subject: wp.subject,
      project_identifier: wp.project.identifier,
      project_name: wp.project.name,
      wp_id: wp.id
    }
  else
    out = {found: false, count: 0}
  end
  File.write("/tmp/initial_wp_state.json", JSON.generate(out))
rescue => e
  File.write("/tmp/initial_wp_state.json", JSON.generate({error: e.message}))
end
RUBY

# Run Ruby script in container
docker exec openproject bash -lc "cd /app && bin/rails runner -e production '/tmp/check_initial.rb'"

# Copy result out of container for local storage/verification
docker cp openproject:/tmp/initial_wp_state.json /tmp/initial_wp_state.json
cat /tmp/initial_wp_state.json

# -----------------------------------------------------------------------
# Prepare Firefox
# -----------------------------------------------------------------------
echo "Launching Firefox to DevOps Automation work packages..."
launch_firefox_to "http://localhost:8080/projects/devops-automation/work_packages" 8

# Maximize and ensure focus
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="