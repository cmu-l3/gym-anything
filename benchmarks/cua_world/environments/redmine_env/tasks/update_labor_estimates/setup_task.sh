#!/bin/bash
set -euo pipefail

echo "=== Setting up update_labor_estimates task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
wait_for_http "$REDMINE_LOGIN_URL" 600

# 1. Seed the specific project and issues using a Ruby script
echo "Seeding project data..."
SEED_SCRIPT="/tmp/seed_estimates_task.rb"

cat > "$SEED_SCRIPT" << 'RUBY'
# Clean up if exists
Project.find_by(identifier: 'office-park-1')&.destroy

# Find admin
admin = User.find_by(login: 'admin')

# Create Project
project = Project.create!(
  name: 'Office Park Phase 1',
  identifier: 'office-park-1',
  description: 'Phase 1 construction of the new commercial park.',
  is_public: true
)
project.set_parent!(nil)
project.enabled_module_names = ['issue_tracking']
project.save!

# Add Admin as member
role = Role.find_by(name: 'Manager') || Role.first
Member.create!(user: admin, project: project, roles: [role])

# Get Tracker and Priorities
tracker = Tracker.first
prio_high = IssuePriority.find_by(name: 'High')
prio_normal = IssuePriority.find_by(name: 'Normal')
prio_low = IssuePriority.find_by(name: 'Low')
status_new = IssueStatus.find_by(name: 'New') || IssueStatus.first
status_closed = IssueStatus.find_by(name: 'Closed') || IssueStatus.where(is_closed: true).first

# Issue Data: [Subject, Priority, Status, InitialHours]
issues_data = [
  ['Excavation Sector A', prio_high, status_new, 0.0],
  ['Excavation Sector B', prio_high, status_new, 0.0],
  ['Foundation Pour Main', prio_high, status_closed, 0.0], # Should be IGNORED
  ['Perimeter Framing', prio_normal, status_new, 0.0],
  ['Interior Framing', prio_normal, status_new, 0.0],
  ['Drywall Installation', prio_normal, status_new, 0.0],
  ['Electrical Rough-in', prio_normal, status_closed, 0.0], # Should be IGNORED
  ['Site Cleanup', prio_low, status_new, 0.0],
  ['Final Inspection', prio_low, status_new, 0.0]
]

issues_data.each do |subj, prio, status, hours|
  Issue.create!(
    project: project,
    tracker: tracker,
    subject: subj,
    priority: prio,
    status: status,
    author: admin,
    estimated_hours: hours,
    start_date: Date.today
  )
end
puts "Seeding complete."
RUBY

# Copy and execute seed script
docker cp "$SEED_SCRIPT" redmine:/tmp/seed_estimates_task.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/seed_estimates_task.rb

# 2. Log in and navigate to the project issues page
TARGET_URL="$REDMINE_BASE_URL/projects/office-park-1/issues"
ensure_redmine_logged_in "$TARGET_URL"

# 3. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="