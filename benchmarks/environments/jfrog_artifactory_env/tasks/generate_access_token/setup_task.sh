#!/bin/bash
echo "=== Setting up generate_access_token task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove output file if it exists
rm -f /home/ga/ci_access_token.txt

# Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Ensure Firefox is running and at the login page
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/login"

# Maximize Firefox for better visibility
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="