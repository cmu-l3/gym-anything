#!/bin/bash
# Setup for: create_legacy_snapshot_repo task
set -e
echo "=== Setting up create_legacy_snapshot_repo task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Verify Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi

# Ensure clean state: Delete the target repository if it already exists
echo "Cleaning up any existing repository..."
delete_repo_if_exists "legacy-dev-local"

# Record initial repository list for 'do nothing' detection
get_repo_count > /tmp/initial_repo_count.txt

# Ensure Firefox is running and ready
echo "Launching/Focusing Firefox..."
ensure_firefox_running "http://localhost:8082"

# Navigate to the Administration page to save agent some clicks (optional, but helpful for stability)
# or just go to home. Let's go to Home to match description flow.
navigate_to "http://localhost:8082/ui/admin/repositories/local"
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="