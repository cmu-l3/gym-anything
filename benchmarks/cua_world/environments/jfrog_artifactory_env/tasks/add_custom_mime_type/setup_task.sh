#!/bin/bash
# Setup for: add_custom_mime_type task
echo "=== Setting up add_custom_mime_type task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi
echo "Artifactory is accessible."

# Check if the MIME type already exists (to prevent pre-completed state)
# We fetch the config and grep for the specific mime type string
CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")
if echo "$CONFIG_XML" | grep -q "application/vnd.company.datalog"; then
    echo "WARNING: Target MIME type already exists in configuration."
    # In a real scenario, we might try to clean it, but modifying the huge XML config via script is risky.
    # We will record this state.
    echo "true" > /tmp/initial_mime_exists.txt
else
    echo "false" > /tmp/initial_mime_exists.txt
fi

# Ensure Firefox is running and navigate to Artifactory Dashboard
# We intentionally do NOT navigate deep into the admin menu to force the agent to find it.
ensure_firefox_running "http://localhost:8082"
sleep 5

# Focus and maximize
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Add custom MIME type 'application/vnd.company.datalog' for extension 'datalog'"