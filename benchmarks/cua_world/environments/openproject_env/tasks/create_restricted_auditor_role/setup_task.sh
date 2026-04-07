#!/bin/bash
echo "=== Setting up create_restricted_auditor_role task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Reset state:
# 1. Delete "External Auditor" role if it exists
# 2. Ensure Carol Williams has "Developer" role on "ecommerce-platform"
echo "Resetting database state..."
op_rails "
  # 1. Remove Role
  r = Role.find_by(name: 'External Auditor')
  r.destroy if r

  # 2. Reset Carol
  u = User.find_by(login: 'carol.williams')
  p = Project.find_by(identifier: 'ecommerce-platform')
  dev_role = Role.find_by(name: 'Developer') || Role.where(builtin: 0).first
  
  if u && p && dev_role
    m = Member.find_by(project: p, principal: u)
    if m
      # Reset roles to just Developer
      m.roles = [dev_role]
      m.save!
    else
      # Create membership
      m = Member.new(project: p, principal: u)
      m.roles = [dev_role]
      m.save!
    end
    puts 'State reset successful'
  else
    puts 'Error finding objects for reset'
  end
"

# Launch Firefox to Login page
launch_firefox_to "http://localhost:8080/login" 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="