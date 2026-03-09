#!/bin/bash
# setup_task.sh for generate_maven_client_config
set -e
echo "=== Setting up generate_maven_client_config task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Artifactory is accessible
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# Ensure 'example-repo-local' exists (it should be default, but verify)
if ! repo_exists "example-repo-local"; then
    echo "WARNING: example-repo-local not found. Creating it..."
    # If missing, we would need to create it, but for this task we assume standard setup.
    # The standard setup script usually ensures this. 
    # Failing loudly if the environment is broken is better than silent failure.
    echo "ERROR: Required repository 'example-repo-local' does not exist."
    exit 1
fi

# Clean up any previous result file to ensure fresh creation
rm -f /home/ga/maven_settings.xml

# Ensure Firefox is running and showing the Artifactory login or home page
# This helps the agent start immediately without waiting for browser launch
ensure_firefox_running "http://localhost:8082/ui/packages"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="