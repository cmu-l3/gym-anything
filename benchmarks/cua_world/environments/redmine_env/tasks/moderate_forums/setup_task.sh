#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up moderate_forums task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Redmine is running and ready
wait_for_http "$REDMINE_LOGIN_URL" 600

# 2. Seed specific data for this task (Project, Boards, Messages)
# We use a temporary Ruby script executed inside the container
SEED_SCRIPT="/tmp/seed_moderate_forums.rb"
cat > "$SEED_SCRIPT" <<EOF
# Create Project
project = Project.find_or_create_by!(identifier: 'community-support') do |p|
  p.name = 'Community Support'
  p.description = 'Support forum for the community.'
  p.is_public = true
end

# Enable boards module
project.enable_module!(:boards)

# Create 'General Discussion' board
board = Board.find_or_create_by!(project: project, name: 'General Discussion') do |b|
  b.description = 'General chatter and announcements.'
end

# Admin user
user = User.find_by_login('admin')

# Create Technical Thread (to be moved)
msg1 = Message.find_or_create_by!(board: board, subject: 'Connection Refused on Port 8080') do |m|
  m.content = 'I am getting a connection refused error when trying to start the service. Logs attached.'
  m.author = user
  m.updated_on = 2.days.ago
  m.created_on = 2.days.ago
end

# Create Old Admin Thread (to be locked)
msg2 = Message.find_or_create_by!(board: board, subject: 'Weekly Sync Notes - Jan 2024') do |m|
  m.content = 'Here are the notes from the last sync.'
  m.author = user
  m.updated_on = 1.month.ago
  m.created_on = 1.month.ago
  m.locked = false # Ensure unlocked initially
end
msg2.update(locked: false) # Force update if it existed

puts "Seeding complete."
EOF

# Copy script to container and execute
docker cp "$SEED_SCRIPT" redmine:/tmp/seed_moderate_forums.rb
docker exec -e SECRET_KEY_BASE=xyz redmine bundle exec rails runner /tmp/seed_moderate_forums.rb

# 3. Launch Firefox and login
TARGET_URL="$REDMINE_BASE_URL/projects/community-support/boards"
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in"
  exit 1
fi

# 4. Final UI setup
focus_firefox || true
sleep 2

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png
log "Initial screenshot captured."

echo "=== Setup complete ==="