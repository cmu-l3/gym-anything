#!/bin/bash
set -e
echo "=== Setting up manage_release_carryover task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Redmine to be ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# 2. Seed specific task data (Project, Versions, Issues)
# We use a Ruby script executed inside the container to ensure correct object creation
echo "Seeding task data via Rails runner..."

cat > /tmp/seed_task_data.rb << 'RUBY'
# Find or create project
project = Project.find_or_create_by(name: 'Orion Avionics', identifier: 'orion-avionics')
project.enabled_module_names = ['issue_tracking', 'versions']
project.trackers = Tracker.all
project.save!

# Create Versions
v_source = Version.find_or_create_by(project: project, name: 'v2.4-stable')
v_source.status = 'open'
v_source.save!

v_target = Version.find_or_create_by(project: project, name: 'v2.5-beta')
v_target.status = 'open'
v_target.save!

# Clear existing issues in this project to ensure clean state
Issue.where(project_id: project.id).destroy_all

# Get statuses
status_new = IssueStatus.find_by(name: 'New') || IssueStatus.first
status_closed = IssueStatus.find_by(name: 'Closed') || IssueStatus.where(is_closed: true).first

tracker = Tracker.first
author = User.where(admin: true).first

# Create "Finished" issues (should stay in v2.4-stable)
keep_ids = []
3.times do |i|
  issue = Issue.create!(
    project: project,
    subject: "Completed Feature implementation #{i+1}",
    description: "This work is done.",
    priority: IssuePriority.first,
    fixed_version: v_source,
    status: status_closed,
    tracker: tracker,
    author: author
  )
  keep_ids << issue.id
end

# Create "Unfinished" issues (should move to v2.5-beta)
move_ids = []
4.times do |i|
  issue = Issue.create!(
    project: project,
    subject: "Pending Bug fix #{i+1} - Carryover",
    description: "This work is not done yet.",
    priority: IssuePriority.first,
    fixed_version: v_source, # Currently in v2.4
    status: status_new,
    tracker: tracker,
    author: author
  )
  move_ids << issue.id
end

# Export IDs for verification
result = {
  project_id: project.id,
  source_version_id: v_source.id,
  target_version_id: v_target.id,
  source_version_name: v_source.name,
  target_version_name: v_target.name,
  ids_to_keep: keep_ids,
  ids_to_move: move_ids,
  initial_timestamp: Time.now.to_i
}

File.open('/tmp/task_setup_data.json', 'w') { |f| f.write(result.to_json) }
RUBY

# Copy seed script to container and execute
docker cp /tmp/seed_task_data.rb redmine:/tmp/seed_task_data.rb
docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bundle exec rails runner /tmp/seed_task_data.rb

# Retrieve the setup data for the export script to use later
docker cp redmine:/tmp/task_setup_data.json /tmp/task_setup_data.json

echo "Task data seeded. Details:"
cat /tmp/task_setup_data.json

# 3. Log in and navigate to the project
# We'll start at the project overview to make the agent find the issues/settings
TARGET_URL="$REDMINE_BASE_URL/projects/orion-avionics"

log "Opening Firefox at: $TARGET_URL"
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine."
  exit 1
fi

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot
focus_firefox || true
sleep 2
take_screenshot /tmp/task_initial.png
log "Initial screenshot captured."

echo "=== Setup complete ==="