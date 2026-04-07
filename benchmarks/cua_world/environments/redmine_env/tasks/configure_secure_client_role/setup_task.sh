#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_secure_client_role task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Redmine to be ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Ensure specific data exists (User: Jordan Lee, Project: Mobile Banking App)
# We use a Ruby script executed inside the container to ensure idempotency
cat > /tmp/ensure_data.rb << 'RUBY'
begin
  # Create User if not exists
  u = User.find_by(login: 'jordan.lee')
  if u.nil?
    u = User.new(
      login: 'jordan.lee',
      firstname: 'Jordan',
      lastname: 'Lee',
      mail: 'jordan.lee@example.com',
      language: 'en'
    )
    u.password = 'Client123!'
    u.password_confirmation = 'Client123!'
    u.save!
    puts "Created user jordan.lee"
  else
    puts "User jordan.lee exists"
  end

  # Create Project if not exists
  p = Project.find_by(identifier: 'mobile-banking')
  if p.nil?
    p = Project.new(
      name: 'Mobile Banking App',
      identifier: 'mobile-banking',
      description: 'Next gen mobile banking application development.'
    )
    p.save!
    # Enable issue tracking module
    p.enabled_module_names = ['issue_tracking', 'files']
    puts "Created project mobile-banking"
  else
    puts "Project mobile-banking exists"
  end

  # Ensure Admin is ready (should be from setup, but just in case)
  a = User.find_by(login: 'admin')
  if a
    a.admin = true
    a.save!
  end
rescue => e
  puts "Error in setup: #{e.message}"
  exit 1
end
RUBY

# Execute the setup script in the container
docker cp /tmp/ensure_data.rb redmine:/tmp/ensure_data.rb
docker exec -e RAILS_ENV=production redmine bundle exec rails runner /tmp/ensure_data.rb

# Log in as Admin and start on the Home page
log "Logging in as admin..."
ensure_redmine_logged_in "$REDMINE_BASE_URL"

# Record initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="