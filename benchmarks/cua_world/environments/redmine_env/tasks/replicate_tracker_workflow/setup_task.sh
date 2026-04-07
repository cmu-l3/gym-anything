#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up replicate_tracker_workflow task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
if ! wait_for_http "$REDMINE_BASE_URL/login" 120; then
  echo "ERROR: Redmine not reachable"
  exit 1
fi

# Create specific Seed Data using Rails Runner
# We need:
# 1. Custom Statuses (New, Review, Approved)
# 2. Custom Role (Junior Engineer)
# 3. Custom Trackers (Design Request, Safety Critical Change)
# 4. Existing Workflow for Design Request

cat > /tmp/seed_workflow_task.rb << 'RUBY'
# Transaction to ensure atomic setup
ActiveRecord::Base.transaction do
  puts "Starting seed..."
  
  # 1. Ensure Statuses
  s_new = IssueStatus.find_by(name: 'New') || IssueStatus.create!(name: 'New', is_closed: false)
  s_review = IssueStatus.find_by(name: 'Review') || IssueStatus.create!(name: 'Review', is_closed: false)
  s_approved = IssueStatus.find_by(name: 'Approved') || IssueStatus.create!(name: 'Approved', is_closed: false)
  
  # 2. Create Role
  role = Role.find_by(name: 'Junior Engineer') || Role.create!(name: 'Junior Engineer', permissions: [:view_issues, :edit_issues])
  
  # 3. Create Trackers
  # Design Request (Source)
  t_source = Tracker.find_by(name: 'Design Request')
  if t_source.nil?
    t_source = Tracker.create!(name: 'Design Request', default_status: s_new)
  end
  
  # Safety Critical Change (Target)
  t_target = Tracker.find_by(name: 'Safety Critical Change')
  if t_target.nil?
    t_target = Tracker.create!(name: 'Safety Critical Change', default_status: s_new)
  end
  
  # Associate trackers with statuses if not already implicit (Redmine requires explicit status-tracker association sometimes, 
  # but Workflow is the main gatekeeper. However, `core_fields` might need setup. 
  # For this task, we assume defaults are fine as long as Workflow exists).
  
  # Clear any existing workflow for these trackers to ensure clean state
  WorkflowTransition.where(tracker_id: [t_source.id, t_target.id]).delete_all
  
  # 4. Populate Source Workflow (Design Request)
  # Junior Engineer can go New -> Review AND New -> Approved
  [s_review, s_approved].each do |target_status|
    WorkflowTransition.create!(
      tracker: t_source,
      role: role,
      old_status: s_new,
      new_status: target_status
    )
  end
  
  # Add a "return" path just to make it realistic
  WorkflowTransition.create!(
    tracker: t_source,
    role: role,
    old_status: s_review,
    new_status: s_new
  )
  
  puts "Seeded: #{t_source.name} (Source) and #{t_target.name} (Target)"
end
RUBY

# Execute the seed script inside the container
echo "Running Rails seed script..."
docker cp /tmp/seed_workflow_task.rb redmine:/tmp/
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/seed_workflow_task.rb

# Login and navigate to Administration
# We direct them to the admin panel to start, as finding "Workflow" is part of the task but logging in is boilerplate
echo "Logging in and navigating..."
ensure_redmine_logged_in "$REDMINE_BASE_URL/admin"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="