#!/bin/bash
set -euo pipefail

echo "=== Setting up export_critical_issues_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists for output
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
# Remove any pre-existing report to prevent false positives
rm -f /home/ga/Documents/critical_site_report.csv

# Wait for Redmine to be reachable
wait_for_http "$REDMINE_LOGIN_URL" 120

# Create Seed Data Script (Ruby)
# This script creates a specific project with a mix of issues to test filtering logic
cat > /tmp/seed_data.rb << 'RUBY'
# Transaction to ensure atomic setup
ActiveRecord::Base.transaction do
  # 1. Create Users
  users = []
  ["Foreman_Mike", "Eng_Sarah", "Safety_Tom"].each do |name|
    u = User.find_by_login(name)
    if u.nil?
      u = User.new(language: 'en', mail: "#{name.downcase}@example.com", firstname: name.split('_')[1], lastname: name.split('_')[0])
      u.login = name
      u.password = 'password'
      u.password_confirmation = 'password'
      u.save!
    end
    users << u
  end

  # 2. Create Project
  project = Project.find_by_identifier('west-side-hwy')
  if project.nil?
    project = Project.create!(name: 'West Side Highway', identifier: 'west-side-hwy', is_public: true)
    project.enable_module!(:issue_tracking)
    project.trackers = Tracker.all
    
    # Add Members
    role_dev = Role.find_by(name: 'Developer') || Role.first
    users.each do |u|
      Member.create!(project: project, user: u, roles: [role_dev])
    end
  end

  # Clear existing issues for this project to ensure exact counts
  Issue.where(project_id: project.id).destroy_all

  # Helper to get references
  tracker = Tracker.first
  author = User.first
  
  priorities = IssuePriority.all
  p_high = priorities.find { |p| p.name == 'High' }
  p_urgent = priorities.find { |p| p.name == 'Urgent' }
  p_normal = priorities.find { |p| p.name == 'Normal' }
  p_low = priorities.find { |p| p.name == 'Low' }

  statuses = IssueStatus.all
  s_new = statuses.find { |s| s.name == 'New' }
  s_closed = statuses.find { |s| s.is_closed? }

  # 3. Create TARGET Issues (Open + High/Urgent) -> Expect 5
  # 3 High, 2 Urgent
  3.times do |i|
    Issue.create!(project: project, subject: "Critical Site Hazard #{i+1}", tracker: tracker, author: author, 
      assigned_to: users.sample, status: s_new, priority: p_high, due_date: Date.today + 5)
  end
  2.times do |i|
    Issue.create!(project: project, subject: "Urgent Material Shortage #{i+1}", tracker: tracker, author: author, 
      assigned_to: users.sample, status: s_new, priority: p_urgent, due_date: Date.today + 2)
  end

  # 4. Create DISTRACTOR Issues (Closed + High/Urgent) -> Expect 0 (Filtered out by Status)
  3.times do |i|
    Issue.create!(project: project, subject: "Resolved Hazard #{i+1}", tracker: tracker, author: author, 
      assigned_to: users.sample, status: s_closed, priority: p_high, due_date: Date.today - 5)
  end

  # 5. Create DISTRACTOR Issues (Open + Normal/Low) -> Expect 0 (Filtered out by Priority)
  5.times do |i|
    Issue.create!(project: project, subject: "Routine Maintenance #{i+1}", tracker: tracker, author: author, 
      assigned_to: users.sample, status: s_new, priority: p_normal, due_date: Date.today + 10)
  end
  
  puts "Seeding complete. Target issues: 5."
end
RUBY

# Execute Seed Script inside container
echo "Running seed script..."
docker cp /tmp/seed_data.rb redmine:/tmp/seed_data.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/seed_data.rb

# Launch Firefox and Login
# Navigate directly to the project issues page to save agent some navigation time
TARGET_URL="$REDMINE_BASE_URL/projects/west-side-hwy/issues"
ensure_redmine_logged_in "$TARGET_URL"

# Focus Firefox
focus_firefox || true
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="