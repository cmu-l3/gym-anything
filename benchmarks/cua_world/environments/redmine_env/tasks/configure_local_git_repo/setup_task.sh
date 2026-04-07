#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Git Repo task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Redmine to be ready
wait_for_http "$REDMINE_BASE_URL" 120

# 2. Create the Project (Core Engine) WITHOUT Repository module enabled
# We use Rails runner to ensure precise setup
echo "Creating project 'Core Engine'..."
docker exec -e SECRET_KEY_BASE="$REDMINE_SKB" redmine bundle exec rails runner "
  p = Project.find_by(identifier: 'core-engine')
  if p
    p.destroy
  end
  
  p = Project.create!(
    name: 'Core Engine',
    identifier: 'core-engine',
    description: 'Core game engine development project.',
    is_public: true,
    inherit_members: false
  )
  # Enable only Issue Tracking initially, explicitly excluding Repository
  p.enabled_module_names = ['issue_tracking', 'time_tracking']
  p.save!
  puts 'Project Core Engine created.'
"

# 3. Create the Bare Git Repository inside the container
# This simulates the server-side repo existing at /srv/git/core-engine.git
echo "Creating git repository inside container..."

docker exec redmine bash -c "
  # Create directory
  mkdir -p /srv/git/core-engine.git
  
  # Initialize bare repo
  git config --global init.defaultBranch main
  git init --bare /srv/git/core-engine.git
  
  # Create a temporary clone to add content (so the repo isn't empty)
  mkdir -p /tmp/core-engine-init
  cd /tmp/core-engine-init
  git init
  git remote add origin /srv/git/core-engine.git
  
  # Add realistic files
  echo '# Core Engine' > README.md
  mkdir src
  echo 'console.log(\"Engine Start\");' > src/engine.js
  echo '{ \"version\": \"1.0.0\" }' > package.json
  
  git config user.email 'devops@example.com'
  git config user.name 'DevOps Bot'
  
  git add .
  git commit -m 'Initial commit'
  git push origin master:main
  
  # Cleanup temp
  rm -rf /tmp/core-engine-init
  
  # Ensure Redmine user owns the repo so it can read it
  chown -R redmine:redmine /srv/git/core-engine.git
"

# 4. Login and Navigate to the project
TARGET_URL="$REDMINE_BASE_URL/projects/core-engine"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

# Focus Firefox
focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
log "Task start screenshot: /tmp/task_initial.png"

echo "=== Task setup complete ==="