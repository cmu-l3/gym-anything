#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up audit_inactive_users task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Wait for Redmine to be reachable
wait_for_http "$REDMINE_BASE_URL" 120

# 2. Create Ruby seed script to inject specific user scenarios
# We use hardcoded dates to ensure the task logic ("before 2026") holds true regardless of when this runs.
cat > /tmp/seed_audit_users.rb << 'RUBY'
# User definition: login, first, last, mail, last_login_date
users = [
  { login: 'bwayne', first: 'Bruce', last: 'Wayne', mail: 'bwayne@example.com', 
    login_date: Time.new(2025, 10, 15, 14, 30, 0, "+00:00") },
  { login: 'ckent', first: 'Clark', last: 'Kent', mail: 'ckent@example.com', 
    login_date: Time.new(2025, 12, 20, 0, 15, 0, "+00:00") },
  { login: 'dprince', first: 'Diana', last: 'Prince', mail: 'dprince@example.com', 
    login_date: Time.new(2026, 2, 14, 9, 0, 0, "+00:00") },
  { login: 'ballen', first: 'Barry', last: 'Allen', mail: 'ballen@example.com', 
    login_date: Time.new(2026, 3, 1, 11, 45, 0, "+00:00") }
]

puts "Seeding users for security audit..."

users.each do |u|
  user = User.find_by_login(u[:login])
  if user
    puts "User #{u[:login]} already exists, resetting status..."
    user.status = 1 # Active
    user.save
  else
    user = User.new
    user.login = u[:login]
    user.firstname = u[:first]
    user.lastname = u[:last]
    user.mail = u[:mail]
    user.password = 'Password123!'
    user.password_confirmation = 'Password123!'
    user.language = 'en'
    user.status = 1 # Active
    if user.save
      puts "Created user #{u[:login]}"
    else
      puts "Failed to save #{u[:login]}: #{user.errors.full_messages.join(', ')}"
      next
    end
  end

  # Force update of timestamps using update_columns to bypass callbacks/timestamps
  # This ensures last_login_on is exactly what we want for the test
  user.update_columns(last_login_on: u[:login_date], created_on: u[:login_date] - 1.year, updated_on: u[:login_date])
  puts "Set #{u[:login]} last_login_on to #{u[:login_date]}"
end
RUBY

# 3. Execute seed script inside container
echo "Injecting user data..."
docker cp /tmp/seed_audit_users.rb redmine:/tmp/seed_audit_users.rb
docker exec -e RAILS_ENV=production -e SECRET_KEY_BASE="$REDMINE_SKB" redmine \
  bundle exec rails runner /tmp/seed_audit_users.rb

# 4. Log in as admin and start at the Administration page
# The task requires navigating to Users, so we start at /admin
TARGET_URL="$REDMINE_BASE_URL/admin"
ensure_redmine_logged_in "$TARGET_URL"

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 2 # Wait for page load
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="