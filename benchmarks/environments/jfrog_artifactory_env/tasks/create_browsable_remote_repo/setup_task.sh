#!/bin/bash
set -e
echo "=== Setting up create_browsable_remote_repo task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# Clean up environment: Delete the repo if it exists to ensure a fresh start
echo "Cleaning up any existing 'maven-explorer' repository..."
# Try to delete via API (best effort)
curl -s -u admin:password -X DELETE "http://localhost:8082/artifactory/api/repositories/maven-explorer" > /dev/null 2>&1 || true

# Record initial state
INITIAL_REPO_COUNT=$(get_repo_count)
echo "$INITIAL_REPO_COUNT" > /tmp/initial_repo_count

# Ensure Firefox is running
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"

# Wait for window and maximize
wait_for_firefox 30
focus_firefox

# Navigate to home to ensure clean UI state
navigate_to "http://localhost:8082/ui/"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="