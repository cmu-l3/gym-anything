#!/bin/bash
set -e
echo "=== Setting up create_repo_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Artifactory to be ready
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Ensure Firefox is running
ensure_firefox_running "http://localhost:8082"

# Check if layout already exists (to ensure clean state)
# We fetch the config XML and check for the specific layout name
echo "Checking for existing layout..."
CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

if echo "$CONFIG_XML" | grep -q "<name>flat-org-layout</name>"; then
    echo "WARNING: Layout 'flat-org-layout' already exists. Attempting to clean up..."
    # Note: Deleting layouts via REST API in OSS is not standard/documented well for specific layouts 
    # without posting the whole config back.
    # For this task setup, we will simply log this. In a real scenario, we might post a filtered config.
    echo "Please ensure environment is clean or ignore if this is a retry."
else
    echo "Layout 'flat-org-layout' does not exist (Clean state verified)."
fi

# Maximize Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="