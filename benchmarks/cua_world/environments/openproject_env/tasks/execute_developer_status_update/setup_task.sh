#!/bin/bash
set -e
echo "=== Setting up execute_developer_status_update task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure we start with a clean browser state, logged in as Admin (to force logout)
#    We use the auth token to verify the API is up, but for the browser, we'll
#    simulate the 'Admin' user being logged in or just land on the project page.
#    Since we can't easily inject a session cookie without UI interaction in this env,
#    we will launch Firefox to the project page. If it requires login, the agent
#    will see the login screen. If 'admin' was cached from setup, they see admin.
#    To ensure a consistent 'need to switch' experience, we'll just go to the project page.

PROJECT_URL="http://localhost:8080/projects/ecommerce-platform/work_packages"

# Launch Firefox
launch_firefox_to "$PROJECT_URL" 10

# 4. Maximize window
maximize_firefox

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="