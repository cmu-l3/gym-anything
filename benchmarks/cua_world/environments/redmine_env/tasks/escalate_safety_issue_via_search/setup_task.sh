#!/bin/bash
set -e
echo "=== Setting up Escalate Safety Issue Task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Create custom data using Rails runner
# We create the project, users, and mix of issues (target + decoys)
cat > /tmp/setup_safety_data.rb << 'RB'
begin
  # 1. Setup Project
  project = Project.find_or_create_by!(name: 'Westside Commercial Complex', identifier: 'westside-complex')
  project.enabled_module_names = ['issue_tracking']
  project.save!

  # 2. Setup Users
  marcus = User.find_by(login: 'mthorne')
  unless marcus
    marcus = User.new(login: 'mthorne', firstname: 'Marcus', lastname: 'Thorne', mail: 'mthorne@example.com')
    marcus.password = 'password123'
    marcus.password_confirmation = 'password123'
    marcus.save!
  end

  sarah = User.find_by(login: 'sjenkins')
  unless sarah
    sarah = User.new(login: 'sjenkins', firstname: 'Sarah', lastname: 'Jenkins', mail: 'sjenkins@example.com')
    sarah.password = 'password123'
    sarah.password_confirmation = 'password123'
    sarah.save!
  end

  # 3. Add Members
  role_dev = Role.find_by(name: 'Developer') || Role.first
  role_mgr = Role.find_by(name: 'Manager') || Role.first
  
  Member.create!(project: project, user: marcus, roles: [role_dev]) unless Member.where(project_id: project.id, user_id: marcus.id).exists?
  Member.create!(project: project, user: sarah, roles: [role_mgr]) unless Member.where(project_id: project.id, user_id: sarah.id).exists?

  # 4. Get Priorities and Trackers
  p_normal = IssuePriority.find_by(name: 'Normal')
  p_high = IssuePriority.find_by(name: 'High')
  p_immediate = IssuePriority.find_by(name: 'Immediate')
  
  tracker_bug = Tracker.find_by(name: 'Bug') || Tracker.first
  tracker_support = Tracker.find_by(name: 'Support') || Tracker.last

  # 5. Create Issues (Target + Decoys)
  # Target
  target = Issue.create!(
    project: project, 
    tracker: tracker_bug, 
    subject: 'Safety Violation: Unsecured scaffolding base in Sector 7', 
    priority: p_normal, 
    author: sarah, 
    status_id: 1,
    description: 'During morning patrol, found base plates missing on section 4 scaffolding in Sector 7.'
  )

  # Decoys
  d1 = Issue.create!(project: project, tracker: tracker_support, subject: 'Procure Ringlock scaffolding for Phase 2', priority: p_high, author: sarah, status_id: 1)
  d2 = Issue.create!(project: project, tracker: tracker_bug, subject: 'Dismantle scaffolding at North Entrance', priority: p_normal, author: marcus, status_id: 1)
  d3 = Issue.create!(project: project, tracker: tracker_bug, subject: 'Sector 7 lighting installation', priority: p_normal, author: sarah, status_id: 1)
  d4 = Issue.create!(project: project, tracker: tracker_support, subject: 'Pour concrete foundation Slab A', priority: p_normal, author: marcus, status_id: 1)

  # Output IDs for verification
  result = {
    target_id: target.id,
    decoy_ids: [d1.id, d2.id, d3.id, d4.id],
    marcus_id: marcus.id,
    immediate_priority_id: p_immediate.id,
    project_identifier: project.identifier
  }
  
  puts result.to_json
rescue => e
  puts({error: e.message}.to_json)
end
RB

echo "Running Rails data setup script..."
docker cp /tmp/setup_safety_data.rb redmine:/tmp/setup_safety_data.rb

# Run script and capture output (last line should be the JSON)
SETUP_OUTPUT=$(docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine bundle exec rails runner /tmp/setup_safety_data.rb)
echo "$SETUP_OUTPUT" | tail -n 1 > /tmp/task_setup_ids.json

# Validate setup
if grep -q "error" /tmp/task_setup_ids.json; then
  echo "ERROR: Data setup failed"
  cat /tmp/task_setup_ids.json
  exit 1
fi

echo "Data setup complete. IDs saved."
cat /tmp/task_setup_ids.json

# Log in Firefox and go to the project overview (not the issue itself, forcing search)
PROJECT_ID=$(jq -r '.project_identifier' /tmp/task_setup_ids.json)
START_URL="$REDMINE_BASE_URL/projects/$PROJECT_ID"

log "Logging in and navigating to $START_URL"
if ! ensure_redmine_logged_in "$START_URL"; then
  echo "ERROR: Failed to login"
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
log "Initial screenshot captured."

echo "=== Setup complete ==="