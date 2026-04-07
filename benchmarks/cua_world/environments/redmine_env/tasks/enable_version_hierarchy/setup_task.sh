#!/bin/bash
set -e
echo "=== Setting up enable_version_hierarchy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable"
  exit 1
fi

# ============================================================
# DATA PREPARATION: Create specific hierarchy and data
# ============================================================
echo "Seeding specific scenario data..."

# Create a Ruby script to set up the exact scenario state
cat > /tmp/setup_scenario.rb << 'RB_EOF'
begin
  # 1. Create Parent Project
  parent = Project.find_by(identifier: 'orbital-platform')
  if parent
    puts "Parent project exists, resetting..."
    parent.versions.destroy_all
    parent.issues.destroy_all
  else
    parent = Project.new(
      name: 'Orbital Platform',
      identifier: 'orbital-platform',
      description: 'Top-level program management for the Orbital Platform.',
      is_public: true,
      inherit_members: true
    )
    parent.save!
  end

  # 2. Create Subproject
  child = Project.find_by(identifier: 'propulsion-system')
  unless child
    child = Project.new(
      name: 'Propulsion System',
      identifier: 'propulsion-system',
      description: 'Engineering subproject for propulsion systems.'
    )
  end
  child.set_parent!(parent)
  child.save!

  # 3. Create Version in Parent (Milestone)
  # CRITICAL: sharing must be 'none' initially so the agent has to fix it
  version = Version.new(
    project: parent,
    name: 'Phase 1 Launch',
    description: 'Initial orbital insertion milestone',
    status: 'open',
    sharing: 'none', 
    effective_date: 3.months.from_now
  )
  version.save!

  # 4. Create Issue in Subproject
  tracker = Tracker.first || Tracker.create!(name: 'Feature', default_status_id: 1)
  status = IssueStatus.first || IssueStatus.create!(name: 'New')
  priority = IssuePriority.find_by(name: 'High') || IssuePriority.first
  author = User.where(admin: true).first

  issue = Issue.new(
    project: child,
    tracker: tracker,
    subject: 'Main Thruster Design',
    description: 'Complete the CAD models for the main thruster assembly.',
    status: status,
    priority: priority,
    author: author,
    start_date: Date.today
    # fixed_version is intentionally nil
  )
  issue.save!

  puts "Scenario setup complete."
  puts "Parent ID: #{parent.id}"
  puts "Child ID: #{child.id}"
  puts "Version ID: #{version.id}"
  puts "Issue ID: #{issue.id}"

rescue => e
  puts "Error in setup: #{e.message}"
  exit 1
end
RB_EOF

# Run the seed script inside the Redmine container
docker cp /tmp/setup_scenario.rb redmine:/tmp/setup_scenario.rb
docker exec -e RAILS_ENV=production redmine bundle exec rails runner /tmp/setup_scenario.rb

# ============================================================
# BROWSER SETUP
# ============================================================
TARGET_URL="$REDMINE_BASE_URL/projects/orbital-platform/settings"

log "Opening Firefox at: $TARGET_URL"

# Log in and navigate to the project settings page
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="