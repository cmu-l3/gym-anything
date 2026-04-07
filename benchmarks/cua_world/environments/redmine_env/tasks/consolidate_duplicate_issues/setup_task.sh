#!/bin/bash
set -e
echo "=== Setting up Consolidate Duplicate Issues Task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable"
  exit 1
fi

# 1. Create Data via Rails Runner
# We need a project and specific issues
echo "Seeding scenario data..."

cat > /tmp/seed_scenario.rb << 'RUBY'
# Find or create project
project = Project.find_by(identifier: 'mobile-app-beta')
if project.nil?
  project = Project.new(
    name: 'Mobile App Beta',
    identifier: 'mobile-app-beta',
    description: 'Beta testing tracker for the new banking app',
    is_public: true
  )
  project.save!
  project.set_parent!(nil)
end

# Enable necessary trackers
project.trackers = Tracker.all

# Create Issues
user = User.find_by(login: 'admin')
tracker = Tracker.find_by(name: 'Bug') || Tracker.first
status_new = IssueStatus.find_by(name: 'New') || IssueStatus.first

# Clear existing issues in this project to ensure clean state
Issue.where(project_id: project.id).destroy_all

issues_data = [
  {
    subject: 'App crashes immediately',
    description: 'I tried to open the app and it closed right away. My phone is a Pixel 6.',
    priority_id: IssuePriority.find_by(name: 'High')&.id
  },
  {
    subject: 'Login screen freeze',
    description: 'White screen on load. Steps: Open app, wait 2 seconds, freeze. Please fix.',
    priority_id: IssuePriority.find_by(name: 'Normal')&.id
  },
  {
    subject: 'CRITICAL: NPE on ActivityStart',
    description: "Crash log attached:\n\njava.lang.NullPointerException: Attempt to invoke virtual method 'void android.view.View.setVisibility(int)' on a null object reference\n\tat com.bank.app.MainActivity.onCreate(MainActivity.java:42)\n\tat android.app.Activity.performCreate(Activity.java:8000)\n\nThis happens on fresh install.",
    priority_id: IssuePriority.find_by(name: 'Urgent')&.id
  },
  {
    subject: 'Bug on startup',
    description: 'Fix this fast please. It does not work.',
    priority_id: IssuePriority.find_by(name: 'Normal')&.id
  }
]

created_ids = []
issues_data.each do |data|
  i = Issue.new(data)
  i.project = project
  i.author = user
  i.tracker = tracker
  i.status = status_new
  i.save!
  created_ids << i.id
end

puts "Created #{created_ids.length} issues in project #{project.name}"
RUBY

# Execute seed script inside container
docker cp /tmp/seed_scenario.rb redmine:/tmp/seed_scenario.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/seed_scenario.rb -e production

# 2. Open Firefox and Log In
TARGET_URL="$REDMINE_BASE_URL/projects/mobile-app-beta/issues"

log "Logging in and navigating to: $TARGET_URL"
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in"
  exit 1
fi

focus_firefox || true
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png
log "Setup complete"