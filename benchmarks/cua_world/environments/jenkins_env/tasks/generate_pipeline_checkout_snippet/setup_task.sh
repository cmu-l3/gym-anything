#!/bin/bash
# Setup script for Generate Pipeline Checkout Snippet task

echo "=== Setting up Generate Pipeline Checkout Snippet Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove existing result file if it exists to ensure fresh creation
rm -f /home/ga/spring_checkout_snippet.groovy

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Ensure Firefox is running and focused on Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    # Start on the dashboard; user must navigate to Pipeline Syntax
    # (Pipeline Syntax is usually at /pipeline-syntax, but let's start at root to test navigation)
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

echo "=== Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Navigate to the 'Pipeline Syntax' snippet generator."
echo "     (Tip: It is accessible from the sidebar of any Pipeline job, or at /pipeline-syntax)"
echo ""
echo "  2. Configure the snippet generator:"
echo "     - Sample Step: checkout: General SCM"
echo "     - SCM: Git"
echo "     - Repository URL: https://github.com/spring-projects/spring-boot.git"
echo "     - Branch to build: 2.7.x"
echo ""
echo "  3. Add 'Additional Behaviours':"
echo "     - Clean before checkout"
echo "     - Prune stale remote-tracking branches"
echo "     - Check out to a sub-directory (Local directory: 'sources')"
echo ""
echo "  4. Generate the script and save it to: /home/ga/spring_checkout_snippet.groovy"
echo ""