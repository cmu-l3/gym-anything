#!/bin/bash
# Task setup: add_project_member
# First removes Carol from DevOps Automation so the agent must re-add her,
# then navigates to the project members settings page.

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_project_member task ==="

wait_for_openproject

# Remove carol.williams from devops-automation project via Rails runner
# so the task is non-trivial (agent must add her)
docker exec openproject bash -c "
    cd /app && bundle exec rails runner \"
project = Project.find_by(identifier: 'devops-automation')
user = User.find_by(login: 'carol.williams')
if project && user
  m = Member.find_by(project: project, principal: user)
  if m
    m.destroy!
    puts 'Removed carol.williams from devops-automation'
  else
    puts 'carol.williams not in devops-automation (already removed)'
  end
end
\" 2>/dev/null" 2>/dev/null || echo "Note: Rails runner for member removal failed (non-fatal)"

sleep 2

launch_firefox_to "http://localhost:8080/login?back_url=http%3A%2F%2Flocalhost%3A8080%2Fprojects%2Fdevops-automation%2Fmembers" 5

take_screenshot /tmp/task_add_project_member_start.png

echo "=== Task setup complete: add_project_member ==="
