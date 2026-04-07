#!/bin/bash
echo "=== Setting up task: create_monthly_billing_report ==="
set -e

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Redmine
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable"
  exit 1
fi

# 2. Seed realistic time entries so the report is meaningful
echo "Seeding time entries..."
cat > /tmp/seed_billing_data.rb <<EOF
begin
  # Create a specific user for billing context if needed, or use admin
  user = User.find_by(login: 'admin')
  
  # Ensure we have a project
  project = Project.first
  if !project
    project = Project.create!(name: 'Billing Test Project', identifier: 'billing-test', tracker_ids: [1])
  end

  # Get an activity
  activity = TimeEntryActivity.first || TimeEntryActivity.create!(name: 'Development')

  # Create entries if count is low
  if TimeEntry.count < 10
    puts "Creating time entries..."
    comments = [
      "Refactoring login API for OAuth2 compliance",
      "Client meeting: Q3 Roadmap discussion",
      "Fixing CSS overflow in dashboard widget",
      "Database migration cleanup",
      "Writing unit tests for payment gateway"
    ]
    
    15.times do |i|
      TimeEntry.create!(
        project: project,
        user: user,
        activity: activity,
        spent_on: Date.today - (i % 5),
        hours: rand(0.5..4.0).round(2),
        comments: comments.sample
      )
    end
    puts "Created 15 time entries."
  else
    puts "Sufficient time entries exist."
  end
rescue => e
  puts "Error seeding data: #{e.message}"
end
EOF

# Copy and run seed script
docker cp /tmp/seed_billing_data.rb redmine:/tmp/seed_billing_data.rb
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner /tmp/seed_billing_data.rb

# 3. Open Firefox and log in
# We start at the Home page, requiring the agent to find "Spent time"
ensure_redmine_logged_in "$REDMINE_BASE_URL"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="