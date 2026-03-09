#!/bin/bash
set -e
echo "=== Setting up Configure Upload Limit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Record initial configuration state
# We query the current configuration to ensure we know the starting point
echo "Recording initial configuration..."
INITIAL_CONFIG=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")
# Extract current limit using grep/sed (simple XML parsing)
INITIAL_LIMIT=$(echo "$INITIAL_CONFIG" | grep -oP '(?<=<fileUploadMaxSize>)[^<]+' || echo "unknown")
echo "$INITIAL_LIMIT" > /tmp/initial_upload_limit.txt
echo "Initial File Upload Limit: $INITIAL_LIMIT"

# Ensure Firefox is running and ready
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082/ui/login"

# Maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="