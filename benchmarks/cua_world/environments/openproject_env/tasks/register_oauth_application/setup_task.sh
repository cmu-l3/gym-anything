#!/bin/bash
echo "=== Setting up OAuth Application Registration Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Remove any pre-existing OAuth app with the target name to ensure fresh creation
echo "Cleaning up existing OAuth applications..."
docker exec openproject bash -c "cd /app && bundle exec rails runner \"Doorkeeper::Application.where(name: 'Jenkins CI Pipeline').destroy_all\"" 2>/dev/null || true

# 2. Clean up: Remove credentials file if it exists
rm -f /home/ga/jenkins_credentials.json

# 3. Wait for OpenProject to be ready
wait_for_openproject

# 4. Launch Firefox to the home page
# We don't go directly to the admin page to force the agent to navigate via the UI
launch_firefox_to "http://localhost:8080/" 5

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="