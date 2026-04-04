#!/bin/bash
set -e
echo "=== Setting up organize_jobs_folders task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be available
wait_for_jenkins_api 120

# Ensure Folders plugin is installed (it's a dependency of workflow-aggregator,
# but let's be explicit to ensure the environment supports folders)
echo "Ensuring cloudbees-folder plugin is installed..."
if ! jenkins_api "pluginManager/api/json?depth=1" 2>/dev/null | grep -q "cloudbees-folder"; then
    echo "Installing cloudbees-folder plugin..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" \
        install-plugin cloudbees-folder 2>/dev/null || true
    
    # Safe restart to load plugin if we had to install it
    echo "Restarting Jenkins to load plugins..."
    java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" \
        safe-restart 2>/dev/null || true
    
    # Wait for restart
    sleep 15
    wait_for_jenkins_api 120
fi

# Record initial state: count of top-level items
INITIAL_ITEMS=$(jenkins_api "api/json" 2>/dev/null | jq '.jobs | length' 2>/dev/null || echo "0")
echo "$INITIAL_ITEMS" > /tmp/initial_item_count.txt
echo "Initial top-level item count: $INITIAL_ITEMS"

# CLEANUP: Delete any pre-existing folders/jobs with our target names to ensure clean state
# This forces the agent to actually create them
echo "Cleaning up any existing task artifacts..."
for item in "platform-team" "frontend-team" "api-service-build" "webapp-build"; do
    if job_exists "$item"; then
        echo "Removing pre-existing item: $item"
        java -jar /tmp/jenkins-cli.jar -s "$JENKINS_URL" -auth "$JENKINS_USER:$JENKINS_PASS" \
            delete-job "$item" 2>/dev/null || true
    fi
done

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Focus and maximize Firefox
wait_for_window "firefox\|mozilla" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Navigate to home
su - ga -c "DISPLAY=:1 xdotool key ctrl+l" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --delay 20 'http://localhost:8080'" 2>/dev/null || true
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="