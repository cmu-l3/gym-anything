#!/bin/bash
# Setup script for Configure Shared Library task
# Cleans up existing library configurations and test jobs

echo "=== Setting up Configure Shared Library Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Clean up Global Shared Libraries config
# We remove the config file from the container to ensure a clean state
echo "Cleaning up Global Shared Libraries configuration..."
docker exec jenkins-server rm -f /var/jenkins_home/org.jenkinsci.plugins.workflow.libs.GlobalLibraries.xml 2>/dev/null || true

# Reload configuration from disk to apply the deletion (clears memory)
# Using Jenkins CLI to reload config
echo "Reloading Jenkins configuration..."
jenkins_cli reload-configuration 2>/dev/null || echo "Reload failed, hoping for the best"

# 2. Delete test job if it exists
JOB_NAME="shared-lib-test"
if job_exists "$JOB_NAME"; then
    echo "Deleting existing job '$JOB_NAME'..."
    jenkins_cli delete-job "$JOB_NAME" 2>/dev/null || true
fi

# 3. Ensure Pipeline Shared Groovy Libraries plugin is installed
# (It's part of workflow-aggregator, but we check to be sure)
echo "Verifying plugin installation..."
PLUGIN_CHECK=$(jenkins_cli list-plugins | grep "pipeline-groovy-lib" || true)
if [ -z "$PLUGIN_CHECK" ]; then
    echo "Installing pipeline-groovy-lib..."
    jenkins_cli install-plugin pipeline-groovy-lib
    jenkins_cli safe-restart
    wait_for_jenkins_api 120
fi

# 4. Prepare browser
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|jenkins" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task Start Time: $(cat /tmp/task_start_time.txt)"