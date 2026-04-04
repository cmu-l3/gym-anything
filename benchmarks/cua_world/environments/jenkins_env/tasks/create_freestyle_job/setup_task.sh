#!/bin/bash
# Setup script for Create Freestyle Job task

echo "=== Setting up Create Freestyle Job Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Record initial job count for verification
echo "Recording initial job count..."
INITIAL_COUNT=$(count_jobs)
printf '%s' "$INITIAL_COUNT" > /tmp/initial_job_count
echo "Initial job count: $INITIAL_COUNT"

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
take_screenshot /tmp/task_start_screenshot.png

echo "=== Create Freestyle Job Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Create a new freestyle project:"
echo "     - Click 'New Item' or 'Create a job'"
echo "     - Enter job name: HelloWorld-Build"
echo "     - Select 'Freestyle project'"
echo "     - Click OK"
echo ""
echo "  2. Configure the job:"
echo "     - Scroll to 'Build Steps' section"
echo "     - Click 'Add build step'"
echo "     - Select 'Execute shell'"
echo "     - Enter command: echo 'Hello from Jenkins!'"
echo ""
echo "  3. Save the job configuration"
echo ""
