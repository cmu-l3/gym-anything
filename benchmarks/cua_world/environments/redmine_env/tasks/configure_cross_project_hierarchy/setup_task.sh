#!/bin/bash
set -e
echo "=== Setting up Configure Cross-Project Hierarchy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is reachable
wait_for_http "$REDMINE_LOGIN_URL" 600

# Create specific projects and issues for this task using Rails Runner
# We also FORCE the setting to be disabled initially
cat > /tmp/setup_data.rb << 'RB'
begin
  # 1. Create Projects
  # Use find_or_create to make it idempotent-ish
  p_strat = Project.find_by(identifier: 'corp-strategy')
  unless p_strat
    p_strat = Project.new(name: 'Corporate Strategy', identifier: 'corp-strategy')
    p_strat.save!
    p_strat.trackers = Tracker.all
    p_strat.enabled_module_names = ['issue_tracking']
    p_strat.save!
  end

  p_prop = Project.find_by(identifier: 'propulsion-sys')
  unless p_prop
    p_prop = Project.new(name: 'Propulsion Systems', identifier: 'propulsion-sys')
    p_prop.save!
    p_prop.trackers = Tracker.all
    p_prop.enabled_module_names = ['issue_tracking']
    p_prop.save!
  end

  # 2. Create Issues
  admin = User.find_by(login: 'admin')
  
  parent = Issue.find_by(subject: 'Next-Gen Thruster Initiative')
  unless parent
    parent = Issue.new(project: p_strat, subject: 'Next-Gen Thruster Initiative', 
                       tracker: Tracker.first, author: admin, status: IssueStatus.first,
                       priority: IssuePriority.find_by(name: 'High') || IssuePriority.first)
    parent.save!
  end

  child = Issue.find_by(subject: 'Cryogenic Fuel Pump Design')
  unless child
    child = Issue.new(project: p_prop, subject: 'Cryogenic Fuel Pump Design',
                      tracker: Tracker.first, author: admin, status: IssueStatus.first,
                      priority: IssuePriority.find_by(name: 'Normal') || IssuePriority.first)
    child.save!
  end

  # 3. Disable cross-project subtasks initially
  # Setting value '' means disabled/restricted to same project usually
  Setting.cross_project_subtasks = '' 

  puts "Setup success: Parent ID #{parent.id}, Child ID #{child.id}"
rescue => e
  puts "Error during setup: #{e.message}"
  exit 1
end
RB

# Execute the setup script inside the container
echo "Seeding task data..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" \
  redmine bundle exec rails runner /tmp/setup_data.rb

# Log in to Redmine and go to Administration page (starting point)
TARGET_URL="$REDMINE_BASE_URL/admin"
log "Logging in and navigating to $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in"
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="