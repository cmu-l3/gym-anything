#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: create_gradle_repo_strict ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is ready
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Clean state: Delete the repository if it already exists
# This ensures the agent must actually create it
echo "Ensuring clean state..."
delete_repo_if_exists "gradle-libs-local"

# Ensure Firefox is running and logged in
# We start at the repository list to make it slightly easier/faster
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/repositories/local"
sleep 5

# Maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="