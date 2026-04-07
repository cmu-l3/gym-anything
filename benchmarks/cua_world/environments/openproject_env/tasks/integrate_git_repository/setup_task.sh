#!/bin/bash
# Setup script for integrate_git_repository task

source /workspace/scripts/task_utils.sh

echo "=== Setting up integrate_git_repository task ==="

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Prepare the bare Git repository inside the OpenProject container
#    The agent cannot access this via filesystem, but OpenProject needs it to exist.
echo "Creating bare git repository in container..."
REPO_PATH="/var/lib/openproject/git/devops.git"

# Create repo and ensure permissions (app user in container usually uid 1000)
docker exec openproject bash -c "
    mkdir -p '${REPO_PATH}' && \
    cd '${REPO_PATH}' && \
    git init --bare && \
    chown -R 1000:1000 '${REPO_PATH}'
" 2>/dev/null

# 3. Ensure the project exists and reset repository state (remove if exists)
echo "Resetting project repository state..."
# Use Rails runner to clear any existing repository for 'devops-automation'
docker exec openproject bash -c "cd /app && bundle exec rails runner \"
    p = Project.find_by(identifier: 'devops-automation')
    if p
      # Disable module initially to force agent to enable it (optional, but good for testing)
      # p.enabled_module_names = p.enabled_module_names - ['repository']
      
      # Destroy existing repo config
      if p.repository
        p.repository.destroy
        puts 'Existing repository configuration removed.'
      end
    else
      puts 'Project not found!'
    end
\"" 2>/dev/null

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox to the project overview
#    We land them on the project page, not directly in settings, to test navigation.
PROJECT_URL="http://localhost:8080/projects/devops-automation"
launch_firefox_to "$PROJECT_URL" 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="