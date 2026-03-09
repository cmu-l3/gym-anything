#!/bin/bash
echo "=== Setting up Configure Snapshot Retention Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Artifactory to be ready
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Ensure clean state: Delete the target repo if it exists
echo "Ensuring target repository does not exist..."
delete_repo_if_exists "project-alpha-snapshots"

# Record initial state
INITIAL_REPO_COUNT=$(get_repo_count)
echo "$INITIAL_REPO_COUNT" > /tmp/initial_repo_count

# Start Firefox and navigate to Repositories page
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/repositories/local"
sleep 5

# Maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="