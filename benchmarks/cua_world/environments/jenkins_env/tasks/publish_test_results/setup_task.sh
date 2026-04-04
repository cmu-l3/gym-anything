#!/bin/bash
# Setup script for Publish Test Results task

echo "=== Setting up Publish Test Results Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Record initial job count
echo "Recording initial job count..."
INITIAL_COUNT=$(count_jobs)
echo "$INITIAL_COUNT" > /tmp/initial_job_count

# Ensure required plugins are installed (junit is usually default, but good to check)
# We won't install here to avoid delay, assuming standard environment has it.
# The 'junit' step is part of 'junit' plugin which is a dependency of 'workflow-aggregator'.

# Clean up any previous attempts if they exist
if job_exists "QA-Test-Suite"; then
    echo "Removing pre-existing QA-Test-Suite job..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" delete-job "QA-Test-Suite" 2>/dev/null || true
fi

# Ensure Firefox is running and focused on Jenkins
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="