#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up archive_completed_project task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

wait_for_http "$REDMINE_BASE_URL" 120

# Create seed script for the Office Relocation project
cat > /tmp/seed_relocation_project.rb << 'EOF'
# Find admin user
admin = User.find_by(login: 'admin')
if admin.nil?
  puts "Admin user not found!"
  exit 1
end

# Create Project if it doesn't exist
project = Project.find_by(identifier: 'office-relocation-2024')
if project
  puts "Project exists, resetting..."
  project.issues.destroy_all
  project.status = 1 # Ensure active
  project.save!
else
  project = Project.new(
    name: 'Office Relocation 2024',
    identifier: 'office-relocation-2024',
    description: 'Tracking tasks for the HQ move to 123 Innovation Drive.',
    is_public: false,
    inherit_members: true
  )
  project.save!
end

# Ensure admin is member
unless project.members.exists?(user_id: admin.id)
  role = Role.find_by(name: 'Manager') || Role.first
  Member.create!(
    project: project,
    user: admin,
    roles: [role]
  )
end

# Create Issues
issues_data = [
  { subject: 'Setup break room coffee machine', tracker: 'Feature', priority: 'Normal' },
  { subject: 'Label network cables in server room', tracker: 'Support', priority: 'Low' },
  { subject: 'Dispose of old CRT monitors', tracker: 'Support', priority: 'Normal' },
  { subject: 'Update emergency exit signage', tracker: 'Bug', priority: 'High' },
  { subject: 'Distribute new keycards', tracker: 'Feature', priority: 'Urgent' }
]

trackers = Tracker.all.index_by(&:name)
priorities = IssuePriority.all.index_by(&:name)
status_new = IssueStatus.find_by(name: 'New') || IssueStatus.first

issues_data.each do |data|
  # Fallback for trackers if names don't match exactly in fresh install
  tracker = trackers[data[:tracker]] || Tracker.first
  
  i = Issue.new(
    project: project,
    subject: data[:subject],
    tracker: tracker,
    priority: priorities[data[:priority]] || IssuePriority.first,
    status: status_new,
    author: admin,
    description: "Task pending from move phase 1."
  )
  i.save!
  puts "Created issue: #{i.subject}"
end
EOF

# Copy and run seed script
echo "Seeding project data..."
docker cp /tmp/seed_relocation_project.rb redmine:/tmp/
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/seed_relocation_project.rb

# Log in and navigate to the project
TARGET_URL="$REDMINE_BASE_URL/projects/office-relocation-2024"
ensure_redmine_logged_in "$TARGET_URL"

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="