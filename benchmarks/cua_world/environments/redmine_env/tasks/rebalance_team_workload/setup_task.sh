#!/bin/bash
echo "=== Setting up Rebalance Team Workload task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is up
wait_for_http "$REDMINE_LOGIN_URL" 600

# Prepare the specific scenario data using a Ruby script executed in the container
cat > /tmp/setup_scenario.rb << 'RBEOF'
# Find or create project
project = Project.find_by(identifier: 'payment-gateway-api')
if project.nil?
  project = Project.create!(name: 'Payment Gateway API', identifier: 'payment-gateway-api', is_public: true)
  project.trackers = Tracker.all
  project.save!
end

# Find or create users
def ensure_user(login, firstname, lastname)
  u = User.find_by(login: login)
  if u.nil?
    u = User.new(login: login, firstname: firstname, lastname: lastname, mail: "#{login}@example.com")
    u.password = 'password123'
    u.password_confirmation = 'password123'
    u.save!
  end
  u
end

mturner = ensure_user('mturner', 'Michael', 'Turner')
jdoe = ensure_user('jdoe', 'Jane', 'Doe')

# Add members to project
role = Role.find_by(name: 'Developer') || Role.first
[mturner, jdoe].each do |u|
  unless Member.where(user_id: u.id, project_id: project.id).exists?
    Member.create!(user: u, project: project, roles: [role])
  end
end

# Clear existing issues for a clean slate if retrying
Issue.where(project_id: project.id).destroy_all

# Create Issues
# 5 High Priority for Michael
# 3 Normal Priority for Michael
# 0 for Jane

high_prio = IssuePriority.find_by(name: 'High') || IssuePriority.create!(name: 'High')
normal_prio = IssuePriority.find_by(name: 'Normal') || IssuePriority.create!(name: 'Normal')
tracker = Tracker.first

issues_data = [
  { subject: "Fix race condition in transaction commit", priority: high_prio },
  { subject: "Handle timeout from upstream provider", priority: high_prio },
  { subject: "Validate currency codes strictly", priority: high_prio },
  { subject: "Encryption key rotation failure", priority: high_prio },
  { subject: "Memory leak in worker process", priority: high_prio },
  { subject: "Update documentation for API v2", priority: normal_prio },
  { subject: "Refactor logging module", priority: normal_prio },
  { subject: "Add unit tests for auth middleware", priority: normal_prio }
]

created_ids = []

issues_data.each do |data|
  i = Issue.new
  i.project = project
  i.tracker = tracker
  i.subject = data[:subject]
  i.priority = data[:priority]
  i.assigned_to = mturner
  i.author = User.find_by(login: 'admin')
  i.status = IssueStatus.first
  i.save!
  created_ids << i.id
end

puts JSON.generate({
  project_id: project.id,
  mturner_id: mturner.id,
  jdoe_id: jdoe.id,
  issue_ids: created_ids
})
RBEOF

# Copy script to container and execute
docker cp /tmp/setup_scenario.rb redmine:/tmp/setup_scenario.rb
echo "Seeding scenario data..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/setup_scenario.rb > /tmp/scenario_data.json

# Extract relevant IDs for verification later
cp /tmp/scenario_data.json /tmp/initial_scenario_state.json

# Log in and navigate to the project issues page
TARGET_URL="$REDMINE_BASE_URL/projects/payment-gateway-api/issues"
echo "Navigating to: $TARGET_URL"

ensure_redmine_logged_in "$TARGET_URL"

# Initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="