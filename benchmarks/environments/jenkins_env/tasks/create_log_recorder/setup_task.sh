#!/bin/bash
set -e
echo "=== Setting up Create Log Recorder Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API to be accessible
echo "Waiting for Jenkins API..."
wait_for_jenkins_api 60

# Record initial state: count existing log recorders
echo "Recording initial state..."
INITIAL_RECORDER_CHECK=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  --data-urlencode 'script=
import jenkins.model.Jenkins
def count = Jenkins.instance.log.recorders.size()
def names = Jenkins.instance.log.recorders.collect { it.name }
println "RECORDER_COUNT=${count}"
println "RECORDER_NAMES=${names}"
' "$JENKINS_URL/scriptText" 2>/dev/null || echo "RECORDER_COUNT=error")

echo "$INITIAL_RECORDER_CHECK" > /tmp/initial_recorder_state.txt
echo "Initial recorder state: $INITIAL_RECORDER_CHECK"

# CLEANUP: Remove any existing log recorder with the target name to ensure a clean start
echo "Ensuring clean state (removing target recorder if exists)..."
curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  --data-urlencode 'script=
import jenkins.model.Jenkins
def targetName = "git-debug-recorder"
def recorder = Jenkins.instance.log.recorders.find { it.name == targetName }
if (recorder) {
    Jenkins.instance.log.recorders.remove(recorder)
    recorder.save()
    println "Removed existing " + targetName
} else {
    println "No existing " + targetName + " found"
}
' "$JENKINS_URL/scriptText" 2>/dev/null || true

# Ensure Firefox is running and focused on Jenkins dashboard
echo "Ensuring Firefox is on Jenkins dashboard..."
MOODLE_URL="http://localhost:8080" # This variable name is a holdover, but URL is correct
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$JENKINS_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Navigate to home to ensure fresh start
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 20 "$JENKINS_URL"
    DISPLAY=:1 xdotool key Return
    sleep 3
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Create log recorder 'git-debug-recorder'"