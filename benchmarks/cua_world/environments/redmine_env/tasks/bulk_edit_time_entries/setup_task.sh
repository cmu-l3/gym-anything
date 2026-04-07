#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up bulk_edit_time_entries task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Redmine is ready
wait_for_http "$REDMINE_BASE_URL" 120

# 2. Seed Data via Rails Runner
# We create a project, a user, and specific time entries (targets and distractors)
echo "Seeding data..."
docker exec -e RAILS_ENV=production redmine bundle exec rails runner '
  # Helper to find or create
  def get_activity(name)
    TimeEntryActivity.find_by(name: name)
  end

  # 1. Setup Project
  project = Project.find_or_create_by!(identifier: "software-migration") do |p|
    p.name = "Software Migration"
    p.is_public = true
  end
  project.enable_module!(:time_tracking)
  project.save!

  # 2. Setup User
  user = User.find_by(login: "junior_dev")
  unless user
    user = User.new(login: "junior_dev", firstname: "Junior", lastname: "Dev", mail: "dev@example.com")
    user.password = "password123"
    user.password_confirmation = "password123"
    user.save!
    # Add to project as Developer
    role = Role.find_by(name: "Developer")
    Member.create!(project: project, user: user, roles: [role])
  end

  # 3. Get Activities
  act_design = get_activity("Design")
  act_dev = get_activity("Development")

  # 4. Create Target Entries (The "Mistake")
  # Clear existing relevant entries to ensure clean state
  TimeEntry.where(project: project, user: user).destroy_all
  
  target_ids = []
  5.times do |i|
    t = TimeEntry.create!(
      project: project,
      user: user,
      author: user,
      hours: 2.0,
      activity: act_design,
      spent_on: Date.today - (i+1).days,
      comments: "Wrong activity log #{i}"
    )
    target_ids << t.id
  end

  # 5. Create Distractor Entries (Admin logging Design - should NOT change)
  admin = User.find_by(login: "admin")
  # Ensure admin is member
  unless Member.find_by(project: project, user: admin)
    Member.create!(project: project, user: admin, roles: [Role.find_by(name: "Manager")])
  end
  
  distractor_ids = []
  3.times do |i|
    t = TimeEntry.create!(
      project: project,
      user: admin,
      author: admin,
      hours: 1.0,
      activity: act_design, # Also Design, but for Admin
      spent_on: Date.today - i.days,
      comments: "Admin valid design work #{i}"
    )
    distractor_ids << t.id
  end

  # Output IDs for tracking
  File.write("/tmp/seed_data_info.json", {
    target_ids: target_ids,
    distractor_ids: distractor_ids
  }.to_json)
'

# Extract seed info from container to host tmp (for export script to use later)
docker cp redmine:/tmp/seed_data_info.json /tmp/seed_data_info.json

# 3. Log in and navigate to the Project's Time Entries page
TARGET_URL="$REDMINE_BASE_URL/projects/software-migration/time_entries"
ensure_redmine_logged_in "$TARGET_URL"

# 4. Final Setup
focus_firefox || true
maximize_active_window

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target IDs and Distractor IDs saved to /tmp/seed_data_info.json"